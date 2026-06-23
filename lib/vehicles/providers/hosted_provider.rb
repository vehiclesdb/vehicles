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
    # NOTE: the public VehiclesDB API is not live yet. This is the wired-up seam:
    # the moment the service ships (and you set `config.api_key`), these methods
    # light up with zero code changes on the consumer's side. Until then they
    # safely return nil. Endpoint shape is provisional — see https://vehiclesdb.org.
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

      def image(model, year:, color:)
        params = {}
        params[:year]  = year  if year
        params[:color] = color if color
        get("/v1/models/#{model.slug}/image", params)&.dig("url")
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
