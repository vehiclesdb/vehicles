# frozen_string_literal: true

require "test_helper"

module Vehicles
  class ConfigurationTest < TestCase
    def test_defaults
      config = Vehicles.configuration

      assert_equal :eu, config.region
      assert_nil config.api_key
      assert_equal "https://api.vehiclesdb.com", config.api_base_url
      assert_equal({}, config.aliases)
    end

    def test_configure_yields_configuration
      Vehicles.configure do |config|
        config.region = :eu
        config.api_key = "secret"
      end

      assert_equal "secret", Vehicles.configuration.api_key
    end

    def test_aliases_are_normalized_on_assignment
      Vehicles.configure { |c| c.aliases = { "Chevy" => "Chevrolet" } }
      # keys are normalized for forgiving lookup; values keep the canonical name
      assert_equal "Chevrolet", Vehicles.configuration.aliases["chevy"]
    end

    def test_custom_alias_resolves_a_make
      assert_nil Vehicles.make("Landy") # not a built-in alias
      Vehicles.configure { |c| c.aliases = { "Landy" => "Land Rover" } }

      assert_equal Vehicles.make("Land Rover"), Vehicles.make("Landy")
      assert_equal Vehicles.models("Land Rover"), Vehicles.models("Landy")
    end

    def test_custom_alias_is_diacritic_and_case_insensitive
      Vehicles.configure { |c| c.aliases = { "Vólks" => "Volkswagen" } }

      assert_equal Vehicles.make("Volkswagen"), Vehicles.make("volks")
    end

    def test_reset_configuration_restores_defaults
      Vehicles.configure do |c|
        c.api_key = "x"
        c.aliases = { "a" => "b" }
      end
      Vehicles.reset_configuration!

      assert_nil Vehicles.configuration.api_key
      assert_equal({}, Vehicles.configuration.aliases)
    end

    def test_aliases_setter_handles_nil
      Vehicles.configure { |c| c.aliases = nil }

      assert_equal({}, Vehicles.configuration.aliases)
    end

    def test_reset_clears_data_path_and_dataset_cache
      original = Vehicles.data_path
      Vehicles.data_path = "/nonexistent/vehicles.json"

      Vehicles.reset_configuration!

      assert_equal original, Vehicles.data_path # back to the bundled default
      refute_empty Vehicles.makes               # dataset reloaded, no stale/poisoned cache
    end
  end
end
