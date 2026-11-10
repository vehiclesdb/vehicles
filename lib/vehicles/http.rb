# frozen_string_literal: true

module Vehicles
  # The one way this gem talks to a VehiclesDB server: a GET capped by
  # `config.api_timeout`, never retried, never raising. Shared by the hosted
  # images provider (keyed, JSON) and the plate templates (public, SVG), so
  # the latency promise and the no-silent-retry rule live in one place.
  module HTTP
    # A finished request. `status` is nil when no response arrived; `error`
    # is then :timeout or :network.
    Response = Struct.new(:status, :body, :error, :uri, :location, keyword_init: true) do
      def success? = status.is_a?(Integer) && status.between?(200, 299)
    end

    # Renamed/merged ids answer a 301 to their successor (RESOLUTION.md §1),
    # and a gem whose data is older or newer than the server's meets them
    # around every release. One hop is the contract; two is slack.
    MAX_REDIRECTS = 2
    REDIRECTS = [301, 302, 303, 307, 308].freeze

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
      response = request(uri, headers)
      response.body if response.success?
    end

    # A Response for a GET, following up to MAX_REDIRECTS redirects that stay
    # on the SAME origin (scheme, host, port) — so the Authorization header
    # never travels to another host. Never raises.
    def request(uri, headers = {}, redirects_left = MAX_REDIRECTS)
      response = once(uri, headers)
      return response unless REDIRECTS.include?(response.status) && redirects_left.positive?

      target = redirect_target(uri, response)
      target ? request(target, headers, redirects_left - 1) : response
    end

    def once(uri, headers)
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

      req = Net::HTTP::Get.new(uri)
      headers.each { |name, value| req[name] = value }
      res = http.request(req)
      Response.new(status: res.code.to_i, body: res.body, uri: uri, location: res["location"])
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      Response.new(status: nil, body: nil, error: :timeout, uri: uri)
    rescue StandardError
      Response.new(status: nil, body: nil, error: :network, uri: uri)
    end

    # The body of a public GET for the dataset refresh (jsDelivr): any
    # redirect is followed (no credentials travel), a longer timeout
    # (`refresh_timeout`), nil on any non-2xx. Labelled UTF-8.
    DOWNLOAD_REDIRECTS = 3

    def download(url, timeout, redirects_left = DOWNLOAD_REDIRECTS)
      require "net/http"
      require "uri"

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout

      response = http.get(uri.request_uri, "Accept" => "application/json")
      case response
      when Net::HTTPSuccess
        # Net::HTTP hands back an ASCII-8BIT body (e.g. after gzip decompression);
        # our datasets are UTF-8 JSON, so label it correctly. Otherwise downstream
        # writes/parses can transcode-raise under Encoding.default_internal = UTF-8.
        response.body&.dup&.force_encoding(Encoding::UTF_8)
      when Net::HTTPRedirection
        return nil if redirects_left <= 0

        download(URI.join(url, response["location"]).to_s, timeout, redirects_left - 1)
      end
    end

    def redirect_target(uri, response)
      return nil if response.location.to_s.empty?

      target = URI.join(uri.to_s, response.location)
      same = target.scheme == uri.scheme && target.host == uri.host && target.port == uri.port
      same ? target : nil
    rescue URI::Error
      nil
    end
  end
end
