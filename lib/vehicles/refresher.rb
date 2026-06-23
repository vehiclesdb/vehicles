# frozen_string_literal: true

require "json"

module Vehicles
  # Pulls the latest published dataset from the VehiclesDB data repo (config.data_url)
  # into a local file cache (config.cache_path). This is how data fixes and new
  # makes reach an app WITHOUT a gem upgrade — schedule `Vehicles.refresh!` (e.g.
  # a daily job) and loads will prefer the cached data over the bundled snapshot.
  #
  # Error-isolated by design: a failed/partial download never corrupts the cache
  # and never raises — the gem just keeps serving whatever it already had
  # (cached, or the bundled snapshot). Atomic write so a reader never sees a
  # half-written file.
  module Refresher
    MAX_REDIRECTS = 3

    module_function

    # Download + cache the latest dataset. Returns true on success, false on any
    # failure (network, non-200, unparseable/empty payload). Never raises.
    def refresh!
      config = Vehicles.configuration
      body = fetch(config.data_url, config.refresh_timeout)
      return false unless valid_payload?(body)

      write_atomic(config.cache_path, body)
      Vehicles.reload! # drop the in-memory dataset so the next access uses fresh data
      true
    rescue StandardError => e
      Vehicles.logger&.warn("[vehicles] refresh failed: #{e.class}: #{e.message}")
      false
    end

    # True when a refreshed dataset is cached on disk.
    def cached?
      path = Vehicles.configuration.cache_path
      !path.to_s.empty? && File.exist?(path)
    end

    def cached_path
      cached? ? Vehicles.configuration.cache_path : nil
    end

    # Remove the cached dataset (the gem falls back to the bundled snapshot).
    def clear_cache!
      path = Vehicles.configuration.cache_path
      File.delete(path) if path && File.exist?(path)
      Vehicles.reload!
    end

    # --- internals -----------------------------------------------------------

    # A payload is only accepted if it parses and looks like our dataset, so a
    # CDN error page / truncated download can never replace good data.
    def valid_payload?(body)
      return false if body.to_s.empty?

      data = JSON.parse(body)
      data.is_a?(Hash) && data["makes"].is_a?(Array) && !data["makes"].empty?
    rescue JSON::ParserError
      false
    end

    def fetch(url, timeout, redirects_left = MAX_REDIRECTS)
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

        fetch(response["location"], timeout, redirects_left - 1)
      end
    end

    def write_atomic(path, body)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.tmp"
      # Binary write: persist the exact bytes, never transcode. Robust regardless
      # of the body's encoding or the app's Encoding.default_internal.
      File.binwrite(tmp, body)
      File.rename(tmp, path) # atomic on the same filesystem
    end
  end
end
