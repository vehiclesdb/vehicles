# frozen_string_literal: true

require "json"

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
    #
    # `years` and `segment` are the wired-up seam for enrichment the API does
    # not serve yet: they answer nil WITHOUT a request (a call to an endpoint
    # that doesn't exist would only cost latency), so the chain falls through
    # to the local data. They light up here when the API ships them.
    module HostedProvider
      # Every VehiclesDB API endpoint lives under this path on
      # `config.api_base_url` (https://vehiclesdb.com/api/v1/...).
      API_PREFIX = "/api/v1"

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
      def image(model, year: nil, color: nil, size: :md)
        images(model, color: color)&.dig("variants", size.to_s, "url")
      end

      # The full images payload for a model — palette, every variant with
      # dimensions, provenance, and the honest color fallback: `color` is what
      # the API actually served, `requested_color` what you asked for (a color
      # that isn't rendered yet falls back rather than 404ing).
      #
      # GET /api/v1/vehicles/:kind/:make_slug/:model_slug/images?color=<slug>
      #
      # `year`/`trim` filters are RESERVED server-side today (the API 422s on
      # them by contract, so callers can't silently build on unimplemented
      # semantics) — which is why `image` accepts `year:` but never sends it:
      # serving the current rendering beats an error until the filter ships.
      def images(model, color: nil)
        params = {}
        params[:color] = color.to_s unless color.to_s.empty?
        get("#{API_PREFIX}/vehicles/#{model.kind}/#{model.make_slug}/#{model.model_slug}/images", params)
      end

      # --- internals -----------------------------------------------------------

      # Issue a keyed GET and parse JSON. Returns nil on ANY failure (network,
      # timeout, non-200, bad JSON) — callers treat nil as "fall back to local
      # data". The wire rules (timeout, no retry) are Vehicles::HTTP's.
      def get(path, params)
        body = HTTP.get(HTTP.url(path, params),
                        "Authorization" => "Bearer #{Vehicles.configuration.api_key}", "Accept" => "application/json")
        body && JSON.parse(body)
      rescue StandardError # bad JSON, a malformed api_base_url
        nil
      end
    end
  end
end
