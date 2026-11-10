# frozen_string_literal: true

require "json"

module Vehicles
  # Pulls the latest published dataset into `config.cache_path`, so data
  # fixes and new makes reach an app WITHOUT a gem upgrade. Schedule
  # `Vehicles.refresh` daily; every process then picks the new file up on its
  # own (Vehicles::DataSource).
  #
  # Safe by construction (0.9.2) — a release is written only when ALL hold:
  #   1. the manifest (`config.manifest_url`, read FIRST, a few KB) announces
  #      a dataset schema this gem reads and a version NEWER than the newest
  #      data the app already has (bundled or cached). Same version → done,
  #      nothing downloaded; older → refused: never a downgrade;
  #   2. the payload is fetched from that exact release (jsDelivr `@latest`
  #      is pinned to the announced version, so the two files cannot come
  #      from different releases), parses, carries that version and schema,
  #      and matches the manifest's per-kind model counts and its sha256
  #      when the manifest publishes one;
  #   3. no kind, and no (kind, country) slice, shrinks below
  #      `config.refresh_min_ratio` (default 0.9) of the data in use: a
  #      release that lost Spain's cars cannot empty a Spanish picker;
  #   4. `config.refresh_guard`, if set, accepts it.
  # Then it is written atomically (temp file + rename in the same
  # directory). A failure at any step leaves the current data untouched.
  # Never raises; returns a Vehicles::RefreshResult.
  module Refresher
    MAX_REDIRECTS = 3

    module_function

    def refresh
      baseline = nil
      outcome = begin
        baseline = baseline_version
        run(baseline)
      rescue StandardError => e
        result(:failed, :error, detail: "#{e.class}: #{e.message}")
      end
      final = RefreshResult.new(**outcome.to_h, previous_version: baseline)
      report(final)
      final
    end

    # Backward compatible boolean: true when the app now has the latest
    # release (just written, or already current).
    def refresh! # rubocop:disable Naming/PredicateMethod -- the pre-0.9.2 boolean API, kept for callers
      refresh.ok?
    end

    # True when a refreshed dataset is cached on disk.
    def cached?
      path = Vehicles.configuration.cache_path
      !path.to_s.empty? && File.exist?(path)
    end

    def cached_path
      cached? ? Vehicles.configuration.cache_path.to_s : nil
    end

    # Remove the cached dataset (the gem falls back to the bundled snapshot).
    def clear_cache!
      path = Vehicles.configuration.cache_path
      File.delete(path) if path && File.exist?(path)
      Vehicles.reload!
    end

    # --- internals -----------------------------------------------------------

    def run(baseline)
      config = Vehicles.configuration
      manifest = nil
      if config.manifest_url
        manifest = parse_json(fetch(config.manifest_url, config.refresh_timeout))
        verdict = manifest_verdict(manifest, baseline)
        return verdict if verdict
      end

      url = manifest ? pinned(config.data_url, manifest["version"]) : config.data_url
      body = fetch(url, config.refresh_timeout)
      return result(:failed, :download_failed, manifest&.dig("version")) if body.to_s.empty?

      payload_verdict(body, manifest, baseline)
    end

    # nil to go on and download; otherwise the result (no manifest, an
    # unsupported schema, or nothing newer).
    def manifest_verdict(manifest, baseline)
      return result(:failed, :manifest_unavailable) unless manifest.is_a?(Hash) && manifest["version"]

      announced = DataSource.version(manifest["version"])
      schema = manifest["dist_schema_version"]
      return result(:rejected, :schema_unsupported, manifest["version"], detail: "schema #{schema}") unless
        DataSource::SCHEMA_VERSIONS.include?(schema)
      return result(:rejected, :invalid_payload, manifest["version"], detail: "manifest version") unless announced

      compare(announced, baseline)
    end

    # A RefreshResult when the parsed payload is not a dataset this gem reads.
    def malformed(data)
      return result(:rejected, :invalid_payload) unless data.is_a?(Hash) && data["makes"].is_a?(Array) &&
                                                        !data["makes"].empty?
      return result(:rejected, :invalid_payload, data["version"], detail: "version") unless
        DataSource.version(data["version"])

      return if DataSource::SCHEMA_VERSIONS.include?(data["schema_version"])

      result(:rejected, :schema_unsupported, data["version"], detail: "schema #{data["schema_version"]}")
    end

    def payload_verdict(body, manifest, baseline)
      data = parse_json(body)
      problem = malformed(data)
      return problem if problem

      version = DataSource.version(data["version"])
      if manifest
        problem = ReleaseChecks.manifest_mismatch(manifest, data, body, dist_key)
        return result(:rejected, *problem.first(1), version, detail: problem[1]) if problem
      end

      verdict = compare(version, baseline)
      return verdict if verdict

      problem = ReleaseChecks.below_floor(data)
      return result(:rejected, :below_floor, version, detail: problem) if problem

      guard = Vehicles.configuration.refresh_guard
      return result(:rejected, :guard, version) if guard && !guard.call(Dataset.new(data), Vehicles.dataset)

      write(body, version)
    end

    # nil when the candidate is newer than what we have; otherwise the result.
    def compare(candidate, baseline)
      return nil if baseline.nil? || candidate > baseline
      return result(:current, nil, candidate) if candidate == baseline

      result(:rejected, :older, candidate)
    end

    def write(body, version)
      path = Vehicles.configuration.cache_path.to_s
      return result(:failed, :write_failed, version, detail: "no cache_path") if path.empty?

      write_atomic(path, body)
      Vehicles.reload!
      result(:updated, nil, version)
    rescue SystemCallError, IOError => e
      result(:failed, :write_failed, version, detail: e.class.name)
    end

    # The newest dataset this app already has: the bundled one, or a usable
    # cache (whatever `use_cache` says — a refresh never writes an older file).
    def baseline_version
      bundled = DataSource.header(Vehicles::DATA_PATH)[:version]
      cache = Vehicles.configuration.cache_path.to_s
      cached = DataSource.usable_cache?(cache) ? DataSource.header(cache)[:version] : nil
      [bundled, cached].compact.max
    end

    # jsDelivr's `@latest` resolves per file and is cached per file, so the
    # manifest and the payload could come from two releases. Ask for the
    # release the manifest announced.
    def pinned(url, version)
      url.to_s.sub("@latest/", "@#{version}/")
    end

    def dist_key
      Vehicles.configuration.data_url.to_s[%r{dist/[^/?#]+\z}] || "dist/vehicles.json"
    end

    def result(status, reason = nil, version = nil, detail: nil)
      RefreshResult.new(status: status, reason: reason, version: version, detail: detail)
    end

    def report(result)
      if result.ok?
        Vehicles.logger&.info("[vehicles] #{result.message}")
      else
        Vehicles.logger&.warn("[vehicles] #{result.message}")
      end
      Vehicles.instrument("refresh.vehicles", result.to_h)
    rescue StandardError
      nil # a broken logger must not turn a refresh into an exception
    end

    def parse_json(body)
      body.to_s.empty? ? nil : JSON.parse(body)
    rescue JSON::ParserError
      nil
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

        fetch(URI.join(url, response["location"]).to_s, timeout, redirects_left - 1)
      end
    end

    def write_atomic(path, body)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      # Binary write: persist the exact bytes, never transcode. Robust regardless
      # of the body's encoding or the app's Encoding.default_internal.
      File.binwrite(tmp, body)
      File.rename(tmp, path) # atomic on the same filesystem
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end
  end
end
