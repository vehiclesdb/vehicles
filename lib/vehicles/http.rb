# frozen_string_literal: true

module Vehicles
  # The one way this gem talks to a VehiclesDB server: a single GET, capped by
  # `config.api_timeout`, never retried, never raising. Shared by the hosted
  # images provider (keyed, JSON) and the plate templates (public, SVG), so
  # the latency promise and the no-silent-retry rule live in one place.
  module HTTP
    module_function

    # `config.api_base_url` + path + query. Plain concatenation, not
    # URI.join: an origin ("http://localhost:3030") and an origin behind a
    # path prefix ("https://proxy.example/vdb") both keep everything they say.
    def url(path, params = {})
      # Lazy-required: the gem is standalone-first, and a key-less install
      # that renders no plates never touches the network.
      require "uri"

      uri = URI("#{Vehicles.configuration.api_base_url.to_s.chomp("/")}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      uri
    end

    # The response body of a 2xx, or nil on ANY failure (network, timeout,
    # non-2xx). Callers treat nil as "fall back".
    def get(uri, headers = {})
      require "net/http"

      config = Vehicles.configuration
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = config.api_timeout
      http.read_timeout = config.api_timeout
      # Net::HTTP silently re-sends an idempotent GET once after a read
      # timeout. That would double the latency we promise to cap AND bill a
      # served image twice, so one request means one request.
      http.max_retries = 0

      request = Net::HTTP::Get.new(uri)
      headers.each { |name, value| request[name] = value }
      response = http.request(request)
      response.body if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      warn "[vehicles] request to VehiclesDB failed (#{e.class}); falling back" if $DEBUG
      nil
    end
  end
end
