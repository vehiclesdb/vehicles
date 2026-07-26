# frozen_string_literal: true

require "json"

module Vehicles
  module Providers
    # Talks to the hosted VehiclesDB API to enrich models with years, images, and
    # segments. It is STRICTLY OPTIONAL: `available?` is true only when an api_key
    # is configured, so a key-less install never reaches the network. Every call
    # is error-isolated — a slow, missing, or failing API yields nil and the
    # resolver falls back to the local data. Tracking/enrichment must never break
    # the host app, so this never raises out.
    #
    # The images endpoint is LIVE (since 2026-07): mint a key at
    # https://vehiclesdb.com/settings/api-keys, set `config.api_key`, and
    # `model.image` / `model.images` answer with rendered vehicle imagery.
    # The enrichment endpoints (years/segment) are still the wired-up seam —
    # they safely return nil until the service ships them.
    module HostedProvider
      module_function

      def available?
        !Vehicles.configuration.api_key.to_s.empty?
      end

      def years(model)
        data = fetch(model)
        return nil unless data && data["year_start"]

        (data["year_start"]..data["year_end"]) # year_end may be nil => endless range
      end

      def segment(model)
        fetch(model)&.dig("segment")&.to_sym
      end

      # One variant URL — the common "just give me an <img src>" case.
      # `size` picks from the API's rendered variants (:sm 320×180, :md
      # 640×360, :lg 1280×720; webp).
      def image(model, year: nil, color: nil, size: :md)
        images(model, color: color)&.dig("variants", size.to_s, "url")
      end

      # The full images payload for a model — palette, every variant with
      # dimensions, provenance, and the honest color fallback: `color` is what
      # the API actually served, `requested_color` what you asked for (a color
      # that isn't rendered yet falls back rather than 404ing).
      #
      # GET /v1/vehicles/:kind/:make_slug/:model_slug/images?color=<slug>
      #
      # `year`/`trim` filters are RESERVED server-side today (the API 422s on
      # them by contract, so callers can't silently build on unimplemented
      # semantics) — which is why `image` accepts `year:` but never sends it:
      # serving the current rendering beats an error until the filter ships.
      def images(model, color: nil)
        params = {}
        params[:color] = color.to_s unless color.to_s.empty?
        get("/v1/vehicles/#{model.kind}/#{model.make_slug}/#{model.model_slug}/images", params)
      end

      # --- internals -----------------------------------------------------------

      # Fetch + memoize the full model payload for this process. Keyed by slug.
      def fetch(model)
        @cache ||= {}
        return @cache[model.slug] if @cache.key?(model.slug)

        @cache[model.slug] = get("/v1/models/#{model.slug}", {})
      end

      def reset!
        @cache = {}
      end

      # Issue a GET and parse JSON. Returns nil on ANY failure (network, timeout,
      # non-200, bad JSON) — callers treat nil as "fall back to local data".
      def get(path, params)
        # Lazy-required: the gem is standalone-first, and this whole module is
        # inert without an api_key, so we don't pay net/http at load time.
        require "net/http"
        require "uri"

        config = Vehicles.configuration
        uri = URI.join(config.api_base_url, path)
        uri.query = URI.encode_www_form(params) unless params.empty?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = config.api_timeout
        http.read_timeout = config.api_timeout

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{config.api_key}"
        request["Accept"] = "application/json"

        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        warn "[vehicles] hosted lookup failed (#{e.class}); using local data" if $DEBUG
        nil
      end
    end
  end
end
