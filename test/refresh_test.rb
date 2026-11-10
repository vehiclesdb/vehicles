# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

module Vehicles
  class RefreshTest < TestCase
    MANIFEST_URL = "https://cdn.jsdelivr.net/gh/vehiclesdb/vehiclesdb@latest/manifest.json"

    def self.payload(version, makes = nil, schema: 2)
      JSON.generate(
        "version" => version, "schema_version" => schema, "region" => "EU",
        "makes" => makes || [{ "name" => "Testmark", "slug" => "testmark", "kinds" => ["car"],
                               "models" => [{ "name" => "Demo", "slug" => "demo",
                                              "kind" => "car", "body_type" => "suv" }] }]
      )
    end

    PAYLOAD = payload("9999.01.0")

    # Multibyte UTF-8 (ë, em dash) — the bytes that break a naive transcode.
    MULTIBYTE_PAYLOAD = JSON.generate(
      "version" => "9999.02.0", "schema_version" => 2, "region" => "EU",
      "source" => "Test — dash",
      "makes" => [{ "name" => "Citroën", "slug" => "citroen", "kinds" => ["car"],
                    "models" => [{ "name" => "C3", "slug" => "c3",
                                   "kind" => "car", "body_type" => "hatchback" }] }]
    )

    def setup
      @dir = Dir.mktmpdir
      @cache = File.join(@dir, "vehicles.json")
      Vehicles.configure do |c|
        c.cache_path = @cache
        c.refresh_min_ratio = nil # the test payloads are one model; the floor has its own tests
      end
      Vehicles.reload!
    end

    def teardown
      Refresher.define_singleton_method(:fetch, @original_fetch) if @original_fetch
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
      super # reset_configuration! + reload!
    end

    def test_active_path_is_bundled_without_a_cache
      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
      assert_operator Vehicles.makes.size, :>, 40
    end

    def test_explicit_data_path_override_beats_the_cache
      serve(PAYLOAD)
      Vehicles.refresh!
      Vehicles.data_path = Vehicles::DATA_PATH

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
    end

    def test_refresh_caches_and_takes_effect_without_a_gem_change
      serve(PAYLOAD)
      result = Vehicles.refresh

      assert_predicate result, :updated?
      assert_equal ["9999.01.0", Vehicles::DataSource.header(Vehicles::DATA_PATH)[:version].to_s],
                   [result.version, result.previous_version]
      assert_path_exists @cache
      assert_equal @cache, Vehicles.active_data_path
      assert_equal "9999.01.0", Vehicles.data_version
      assert_equal ["Testmark"], Vehicles.makes
    end

    def test_the_payload_is_fetched_from_the_announced_release
      serve(PAYLOAD)
      Vehicles.refresh

      assert_includes @fetched, "https://cdn.jsdelivr.net/gh/vehiclesdb/vehiclesdb@9999.01.0/dist/vehicles.json"
    end

    def test_use_cache_false_always_serves_bundled
      serve(PAYLOAD)
      Vehicles.refresh!
      Vehicles.configure { |c| c.use_cache = false }
      Vehicles.reload!

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
      assert_operator Vehicles.makes.size, :>, 40
    end

    def test_refresh_returns_false_and_keeps_data_on_network_failure
      serve(nil) # non-200 / unreachable

      refute Vehicles.refresh!
      assert_equal :download_failed, Vehicles.refresh.reason
      refute_path_exists @cache
      assert_operator Vehicles.makes.size, :>, 40 # still bundled
    end

    def test_no_manifest_no_download
      serve(PAYLOAD, manifest: nil)
      result = Vehicles.refresh

      assert_equal %i[failed manifest_unavailable], [result.status, result.reason]
      assert_equal [MANIFEST_URL], @fetched
    end

    def test_refresh_rejects_a_garbage_payload
      serve("<html>500</html>")

      refute Vehicles.refresh!
      refute_path_exists @cache
    end

    def test_refresh_rejects_empty_makes
      serve(JSON.generate("version" => "9999.01.0", "schema_version" => 2, "makes" => []))

      assert_equal :invalid_payload, Vehicles.refresh.reason
    end

    def test_refresh_never_raises
      skip "mocha not available" unless defined?(Mocha)
      Refresher.stubs(:fetch).raises(StandardError, "boom")

      result = Vehicles.refresh # swallowed + logged, not propagated

      assert_equal %i[failed error], [result.status, result.reason]
      refute Vehicles.refresh!
    end

    def test_a_failed_refresh_does_not_clobber_a_good_cache
      serve(PAYLOAD)
      Vehicles.refresh!
      serve(nil, manifest: manifest("9999.02.0")) # a newer release whose download fails

      refute Vehicles.refresh!
      assert_equal "9999.01.0", Vehicles.data_version # kept the good cache
    end

    def test_clear_cache_falls_back_to_bundled
      serve(PAYLOAD)
      Vehicles.refresh!

      Refresher.clear_cache!

      refute_path_exists @cache
      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
    end

    # Regression: a real Net::HTTP body is ASCII-8BIT (e.g. gzip-decompressed)
    # and our data has multibyte UTF-8; under Encoding.default_internal = UTF-8
    # (as Rails sets) a naive File.write transcode-raised. Must round-trip cleanly.
    def test_refresh_survives_a_binary_body_with_multibyte_chars_under_utf8_internal
      prev_internal = Encoding.default_internal
      Encoding.default_internal = Encoding::UTF_8
      serve(MULTIBYTE_PAYLOAD.dup.force_encoding(Encoding::ASCII_8BIT), manifest: manifest("9999.02.0"))

      assert Vehicles.refresh!
      assert_path_exists @cache
      assert_includes Vehicles.makes, "Citroën" # bytes preserved + readable
    ensure
      Encoding.default_internal = prev_internal
    end

    # --- 0.9.2: what a refresh refuses ---------------------------------------

    def test_the_same_version_is_current_and_downloads_nothing
      serve(PAYLOAD)
      Vehicles.refresh
      @fetched.clear

      result = Vehicles.refresh

      assert_equal :current, result.status
      assert_predicate result, :ok?
      assert_equal [MANIFEST_URL], @fetched
    end

    def test_an_older_release_is_refused_never_a_downgrade
      serve(self.class.payload("2020.01.0"), manifest: manifest("2020.01.0"))
      result = Vehicles.refresh

      assert_equal %i[rejected older], [result.status, result.reason]
      refute_path_exists @cache
    end

    def test_an_older_payload_behind_a_newer_manifest_is_refused
      serve(self.class.payload("2020.01.0"), manifest: manifest("9999.01.0"))

      assert_equal :version_mismatch, Vehicles.refresh.reason
    end

    def test_an_unsupported_schema_is_refused_before_the_download
      serve(PAYLOAD, manifest: manifest("9999.01.0", schema: 3))
      result = Vehicles.refresh

      assert_equal %i[rejected schema_unsupported], [result.status, result.reason]
      assert_equal [MANIFEST_URL], @fetched
    end

    def test_an_unsupported_payload_schema_is_refused
      serve(self.class.payload("9999.01.0", schema: 3))

      assert_equal :schema_unsupported, Vehicles.refresh.reason
    end

    def test_model_counts_must_match_the_manifest
      serve(PAYLOAD, manifest: manifest("9999.01.0", cars: 7))
      result = Vehicles.refresh

      assert_equal :count_mismatch, result.reason
      assert_match "car: 1 ≠ 7", result.message
    end

    def test_a_published_checksum_is_verified
      serve(PAYLOAD, manifest: manifest("9999.01.0", sha256: "0" * 64))

      assert_equal :checksum_mismatch, Vehicles.refresh.reason

      serve(PAYLOAD, manifest: manifest("9999.01.0", sha256: Digest::SHA256.hexdigest(PAYLOAD)))

      assert_predicate Vehicles.refresh, :updated?
    end

    def test_published_bytes_are_verified
      bad = JSON.parse(manifest("9999.01.0"))
      bad["dist_files"] = { "dist/vehicles.json" => { "bytes" => PAYLOAD.bytesize + 1 } }
      serve(PAYLOAD, manifest: JSON.generate(bad))

      assert_equal :checksum_mismatch, Vehicles.refresh.reason
    end

    # A release that lost most of a country's cars must not empty that
    # country's pickers: the default floor compares every kind and every
    # (kind, country) slice with the data in use.
    def test_a_release_far_smaller_than_the_data_in_use_is_refused
      Vehicles.configure { |c| c.refresh_min_ratio = 0.9 }
      serve(PAYLOAD)
      result = Vehicles.refresh

      assert_equal %i[rejected below_floor], [result.status, result.reason]
      refute_path_exists @cache
    end

    def test_refresh_guard_has_the_last_word
      seen = nil
      Vehicles.configure do |c|
        c.refresh_guard = lambda do |candidate, current|
          seen = [candidate.version, current.version]
          false
        end
      end
      serve(PAYLOAD)

      assert_equal :guard, Vehicles.refresh.reason
      assert_equal "9999.01.0", seen.first
      refute_path_exists @cache
    end

    def test_without_a_manifest_url_the_payload_is_still_checked
      Vehicles.configure { |c| c.manifest_url = nil }
      serve(self.class.payload("2020.01.0"), manifest: nil)

      assert_equal :older, Vehicles.refresh.reason
      serve(PAYLOAD, manifest: nil)

      assert_predicate Vehicles.refresh, :updated?
    end

    def test_a_custom_data_url_derives_its_manifest
      Vehicles.configure { |c| c.data_url = "https://mirror.example/vdb/dist/vehicles.json" }

      assert_equal "https://mirror.example/vdb/manifest.json", Vehicles.configuration.manifest_url
      Vehicles.configure { |c| c.data_url = "https://mirror.example/vehicles.json" }

      assert_nil Vehicles.configuration.manifest_url
    end

    # --- 0.9.2: which file a process serves -----------------------------------

    def test_a_cache_older_than_the_bundled_data_is_ignored
      File.write(@cache, self.class.payload("2020.01.0"))
      Vehicles.reload!

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
      assert_operator Vehicles.makes.size, :>, 40
    end

    def test_a_cache_with_another_schema_is_ignored
      File.write(@cache, self.class.payload("9999.01.0", schema: 3))
      Vehicles.reload!

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
    end

    # Another process (a job, another container on a shared volume) promotes
    # a file: this process adopts it on its own, no reload!, no restart.
    def test_every_process_adopts_a_newly_promoted_file
      Vehicles.configure { |c| c.reload_check_interval = 0 }
      bundled = Vehicles.data_version
      File.write(@cache, PAYLOAD)

      assert_equal "9999.01.0", Vehicles.data_version
      File.write("#{@cache}.tmp", MULTIBYTE_PAYLOAD)
      File.rename("#{@cache}.tmp", @cache)

      assert_equal "9999.02.0", Vehicles.data_version
      # Never back to older data on its own: a deleted (or older, or broken)
      # cache keeps the newer dataset in memory until an explicit reload!.
      File.delete(@cache)

      assert_equal "9999.02.0", Vehicles.data_version
      Vehicles.reload!

      assert_equal bundled, Vehicles.data_version
    end

    # Astra r2: the in-memory dataset counts as "what we have".
    def test_a_release_older_than_the_data_in_memory_is_refused
      Vehicles.configure { |c| c.reload_check_interval = 0 }
      File.write(@cache, MULTIBYTE_PAYLOAD) # 9999.02.0 adopted…

      assert_equal "9999.02.0", Vehicles.data_version
      File.delete(@cache) # …then the file disappears; memory keeps 9999.02.0
      serve(PAYLOAD) # a stale CDN announces 9999.01.0

      assert_equal(%i[rejected older], Vehicles.refresh.then { |r| [r.status, r.reason] })
    end

    # Astra r2: the floor is re-checked under the lock against the newest file.
    def test_the_floor_is_rechecked_against_a_release_promoted_meanwhile
      Vehicles.configure { |c| c.refresh_min_ratio = 0.9 }
      many = (1..30).map { |i| { "name" => "M#{i}", "slug" => "m#{i}", "kind" => "car", "availability" => ["es"] } }
      big = [{ "name" => "Testmark", "slug" => "testmark", "kinds" => ["car"], "models" => many }]
      File.write(@cache, self.class.payload("9999.01.0", big)) # promoted by "another worker"
      small = JSON.parse(PAYLOAD).merge("version" => "9999.02.0")

      result = Refresher.write(JSON.generate(small), DataSource.version("9999.02.0"), small)

      assert_equal %i[rejected below_floor], [result.status, result.reason]
    end

    # Astra r2: what is parsed is checked, not only the header read earlier.
    def test_a_file_swapped_after_its_header_was_read_is_checked_again
      File.write(@cache, PAYLOAD)
      DataSource.header(@cache) # header cached for this stamp…
      File.write(@cache, self.class.payload("9999.01.0", schema: 3)) # …same size, new schema

      assert_raises(DataSource::Error) { DataSource.build(@cache) }
    end

    def test_a_parseable_file_without_makes_never_replaces_the_data
      Vehicles.configure { |c| c.reload_check_interval = 0 }
      File.write(@cache, PAYLOAD)

      assert_equal "9999.01.0", Vehicles.data_version
      File.write(@cache, JSON.generate("version" => "9999.05.0", "schema_version" => 2, "makes" => []))

      assert_equal ["Testmark"], Vehicles.makes
    end

    def test_a_model_that_does_not_build_is_refused
      broken = JSON.parse(PAYLOAD)
      broken["makes"][0]["models"][0]["regions"] = 7
      serve(JSON.generate(broken))

      assert_equal :invalid_payload, Vehicles.refresh.reason
      refute_path_exists @cache
    end

    def test_a_refresh_finished_after_a_newer_one_does_not_downgrade
      serve(MULTIBYTE_PAYLOAD, manifest: manifest("9999.02.0"))

      assert_predicate Vehicles.refresh, :updated?
      # A slower worker that started on 9999.01.0 reaches its write now.
      result = Refresher.write(PAYLOAD, DataSource.version("9999.01.0"))

      assert_equal %i[rejected older], [result.status, result.reason]
      assert_equal "9999.02.0", Vehicles.data_version
    end

    def test_the_check_is_throttled
      Vehicles.configure { |c| c.reload_check_interval = 3600 }
      bundled = Vehicles.data_version
      File.write(@cache, PAYLOAD)

      assert_equal bundled, Vehicles.data_version # not looked at yet
      Vehicles.reload!

      assert_equal "9999.01.0", Vehicles.data_version
    end

    def test_a_corrupt_file_never_replaces_the_data_in_memory
      Vehicles.configure { |c| c.reload_check_interval = 0 }
      File.write(@cache, PAYLOAD)

      assert_equal "9999.01.0", Vehicles.data_version
      File.write(@cache, %({"version": "9999.03.0", "schema_version": 2, "makes": [ truncated))

      assert_equal "9999.01.0", Vehicles.data_version
      assert_equal ["Testmark"], Vehicles.makes
    end

    def test_cache_dir_sets_the_shared_location
      Vehicles.configure { |c| c.cache_dir = "/shared/vehicles" }

      assert_equal "/shared/vehicles/vehicles.json", Vehicles.configuration.cache_path
      assert_equal "/shared/vehicles", Vehicles.configuration.cache_dir
    end

    def test_regions_follow_the_dataset
      Vehicles.data_path = File.join(@dir, "x.json").tap { |p| File.write(p, PAYLOAD) }

      assert_empty Vehicles.regions
      Vehicles.data_path = nil

      refute_empty Vehicles.regions
    end

    private

    def manifest(version, schema: 2, cars: 1, sha256: nil)
      m = { "version" => version, "dist_schema_version" => schema, "kinds" => { "car" => { "models" => cars } } }
      m["dist_files"] = { "dist/vehicles.json" => { "sha256" => sha256 } } if sha256
      JSON.generate(m)
    end

    # The manifest URL answers `manifest` (default: announces the payload's
    # own version), every other URL answers `body`. Records what was fetched.
    def serve(body, manifest: :auto)
      if manifest == :auto
        version = begin
          body && JSON.parse(body)["version"]
        rescue JSON::ParserError
          nil
        end
        manifest = manifest(version || "9999.01.0")
      end
      fetched = @fetched = []
      @original_fetch ||= Refresher.method(:fetch)
      Refresher.define_singleton_method(:fetch) do |url, *|
        fetched << url
        url == MANIFEST_URL ? manifest : body
      end
    end
  end
end
