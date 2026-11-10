# frozen_string_literal: true

require "json"
require "time"

module Vehicles
  module Providers
    # Talks to the hosted VehiclesDB API for vehicle imagery. It is STRICTLY
    # OPTIONAL: `available?` is true only when an api_key is configured, so a
    # key-less install never reaches the network. Every call is error-isolated
    # — a slow, missing, or failing API yields nil and the resolver falls back
    # to the local data. Enrichment must never break the host app, so this
    # never raises out.
    #
    # The images endpoint is LIVE (since 2026-07): mint a key at
    # https://vehiclesdb.com/settings/api-keys, set `config.api_key`, and
    # `model.image` / `model.images` answer with rendered vehicle imagery.
    # Since 0.9.2:
    #   - a renamed/merged id's 301 is followed (same origin only);
    #   - failures are no longer silent: `model.images_result` says why
    #     (Vehicles::HostedResult), and 401/402/403/429/5xx/timeouts go to
    #     `config.on_hosted_error` and a warn log line;
    #   - payloads are cached (`config.image_cache`), so a page view does not
    #     pay per render;
    #   - `year:` is sent, not dropped (the API answers 422
    #     `unsupported_filter` until year-accurate renders ship);
    #   - `exact_color: true` refuses the API's honest color fallback.
    #
    # `years` and `segment` are the wired-up seam for enrichment the API does
    # not serve yet: they answer nil WITHOUT a request, so the chain falls
    # through to the local data.
    module HostedProvider
      # Every VehiclesDB API endpoint lives under this path on
      # `config.api_base_url` (https://vehiclesdb.com/api/v1/...).
      API_PREFIX = "/api/v1"
      CACHE_SCOPE = "vehicles/images/v1"
      # A cached hit is dropped this long before the payload's own
      # `expires_at`, so a served URL never dies in a visitor's browser.
      EXPIRY_MARGIN = 3600

      module_function

      def available?
        !Vehicles.configuration.api_key.to_s.empty?
      end

      def years(_model)
        nil
      end

      def segment(_model)
        nil
      end

      # One variant URL — the common "just give me an <img src>" case.
      # `size` picks from the API's rendered variants (:sm 320×180, :md
      # 640×360, :lg 1280×720; webp).
      def image(model, year: nil, color: nil, size: :md, exact_color: false)
        images_result(model, year: year, color: color, exact_color: exact_color).url(size)
      end

      # The full images payload (palette, every variant with dimensions,
      # provenance, `color` served vs `requested_color` asked), or nil.
      def images(model, color: nil, year: nil, exact_color: false)
        result = images_result(model, color: color, year: year, exact_color: exact_color)
        result.ok? ? result.payload : nil
      end

      # GET /api/v1/vehicles/:kind/:make_slug/:model_slug/images — a
      # Vehicles::HostedResult, never nil, never raises.
      def images_result(model, color: nil, year: nil, exact_color: false)
        return HostedResult.new(reason: :no_api_key) unless available?

        color = color.to_s.empty? ? nil : color.to_s
        path = "#{API_PREFIX}/vehicles/#{model.id}/images"
        if exact_color && color && (palette = cache_read(palette_key(model))) && !palette.include?(color)
          return HostedResult.new(reason: :color_not_rendered, path: path, cached: true)
        end

        result = cached_or_fetch(model, path, color, year)
        exact_color && color && result.ok? && result.payload["color"] != color ? unrendered(result) : result
      rescue StandardError => e
        HostedResult.new(reason: :invalid_response, error: e.class.name, path: path)
      end

      # --- internals -----------------------------------------------------------

      def cached_or_fetch(model, path, color, year)
        key = cache_key(model, color, year)
        hit = cache_read(key)
        return from_cache(hit, path) if hit.is_a?(Hash)

        result = fetch(path, { color: color, year: year }.compact.transform_values(&:to_s))
        remember(model, key, result)
        notify(result)
        result
      end

      # A keyed GET → HostedResult.
      def fetch(path, params)
        response = HTTP.request(HTTP.url(path, params),
                                "Authorization" => "Bearer #{Vehicles.configuration.api_key}",
                                "Accept" => "application/json")
        return HostedResult.new(reason: response.error, path: path) if response.status.nil?

        body = parse(response.body)
        unless response.success?
          error = body.is_a?(Hash) ? body["error"] : nil
          return HostedResult.from_status(response.status, body_error: error, path: path)
        end
        return HostedResult.new(reason: :invalid_response, status: response.status, path: path) unless
          body.is_a?(Hash) && body["variants"].is_a?(Hash)

        HostedResult.new(reason: :ok, status: response.status, payload: body, path: path)
      end

      def unrendered(result)
        result.with(reason: :color_not_rendered)
      end

      def remember(model, key, result)
        if result.ok?
          cache_write(key, { "payload" => result.payload, "status" => result.status }, hit_ttl(result.payload))
          palette = result.payload["palette"]
          cache_write(palette_key(model), palette, hit_ttl(result.payload)) if palette.is_a?(Array)
        elsif result.reason == :not_found
          cache_write(key, { "status" => result.status, "error" => result.error },
                      Vehicles.configuration.image_miss_ttl)
        end
      end

      def from_cache(entry, path)
        if entry["payload"]
          HostedResult.new(reason: :ok, status: entry["status"], payload: entry["payload"], path: path, cached: true)
        else
          HostedResult.from_status(entry["status"], body_error: entry["error"], path: path).with(cached: true)
        end
      end

      def hit_ttl(payload)
        ttl = Vehicles.configuration.image_cache_ttl
        expires = payload["expires_at"] && Time.iso8601(payload["expires_at"].to_s)
        expires ? [ttl, (expires - Time.now - EXPIRY_MARGIN).to_i].min : ttl
      rescue ArgumentError
        ttl
      end

      # Alerts → `config.on_hosted_error` + one warn line + an
      # ActiveSupport notification ("request.vehicles") for every call.
      # The path carries a model id and nothing else (no query string).
      def notify(result)
        Vehicles.instrument("request.vehicles", result.to_h)
        return unless result.alert?

        Vehicles.logger&.warn("[vehicles] #{result.message}")
        Vehicles.configuration.on_hosted_error&.call(result)
      rescue StandardError
        nil # a broken callback must never break a page
      end

      def parse(body)
        body.to_s.empty? ? nil : JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      # The base URL is in the key so a development server's answers never
      # serve production; the year/color complete the request identity.
      def cache_key(model, color, year)
        [CACHE_SCOPE, Vehicles.configuration.api_base_url, model.id, color || "-", year || "-"].join("|")
      end

      def palette_key(model)
        [CACHE_SCOPE, Vehicles.configuration.api_base_url, model.id, "palette"].join("|")
      end

      def cache_read(key)
        Vehicles.configuration.image_cache&.read(key)
      rescue StandardError
        nil
      end

      def cache_write(key, value, ttl)
        return if ttl.to_i <= 0

        Vehicles.configuration.image_cache&.write(key, value, expires_in: ttl)
      rescue StandardError
        nil
      end
    end
  end
end
