# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

module Vehicles
  class RefreshTest < TestCase
    PAYLOAD = JSON.generate(
      "version" => "9999.01.0", "schema_version" => 2, "region" => "EU",
      "makes" => [{ "name" => "Testmark", "slug" => "testmark", "kinds" => ["car"],
                    "models" => [{ "name" => "Demo", "slug" => "demo",
                                   "kind" => "car", "body_type" => "suv" }] }]
    )

    def setup
      @dir = Dir.mktmpdir
      @cache = File.join(@dir, "vehicles.json")
      Vehicles.configure { |c| c.cache_path = @cache }
      Vehicles.reload!
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
      super # reset_configuration! + Dataset.reset!
    end

    def test_active_path_is_bundled_without_a_cache
      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
      assert_operator Vehicles.makes.size, :>, 40
    end

    def test_explicit_data_path_override_beats_the_cache
      stub_fetch(PAYLOAD)
      Vehicles.refresh!
      Vehicles.data_path = Vehicles::DATA_PATH

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
    end

    def test_refresh_caches_and_takes_effect_without_a_gem_change
      stub_fetch(PAYLOAD)

      assert Vehicles.refresh!
      assert_path_exists @cache
      assert_equal @cache, Vehicles.active_data_path
      assert_equal "9999.01.0", Vehicles.data_version
      assert_equal ["Testmark"], Vehicles.makes
    end

    def test_use_cache_false_always_serves_bundled
      stub_fetch(PAYLOAD)
      Vehicles.refresh!
      Vehicles.configure { |c| c.use_cache = false }
      Vehicles.reload!

      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
      assert_operator Vehicles.makes.size, :>, 40
    end

    def test_refresh_returns_false_and_keeps_data_on_network_failure
      stub_fetch(nil) # non-200 / unreachable

      refute Vehicles.refresh!
      refute_path_exists @cache
      assert_operator Vehicles.makes.size, :>, 40 # still bundled
    end

    def test_refresh_rejects_a_garbage_payload
      stub_fetch("<html>500</html>")

      refute Vehicles.refresh!
      refute_path_exists @cache
    end

    def test_refresh_rejects_empty_makes
      stub_fetch(JSON.generate("version" => "x", "makes" => []))

      refute Vehicles.refresh!
    end

    def test_refresh_never_raises
      skip "mocha not available" unless defined?(Mocha)
      Refresher.stubs(:fetch).raises(StandardError, "boom")

      refute Vehicles.refresh! # swallowed + logged, not propagated
    end

    def test_a_failed_refresh_does_not_clobber_a_good_cache
      stub_fetch(PAYLOAD)
      Vehicles.refresh!
      stub_fetch(nil) # next refresh fails

      refute Vehicles.refresh!
      assert_equal "9999.01.0", Vehicles.data_version # kept the good cache
    end

    def test_clear_cache_falls_back_to_bundled
      stub_fetch(PAYLOAD)
      Vehicles.refresh!

      Refresher.clear_cache!

      refute_path_exists @cache
      assert_equal Vehicles::DATA_PATH, Vehicles.active_data_path
    end

    private

    def stub_fetch(value)
      skip "mocha not available" unless defined?(Mocha)
      Refresher.stubs(:fetch).returns(value)
    end
  end
end
