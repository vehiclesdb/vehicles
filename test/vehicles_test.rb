# frozen_string_literal: true

require "test_helper"

module Vehicles
  class VehiclesTest < TestCase
    # --- meta ----------------------------------------------------------------

    def test_data_version_is_present
      assert_match(/\A\d{4}\.\d{2}\.\d+\z/, Vehicles.data_version)
    end

    def test_region_is_eu
      assert_equal :eu, Vehicles.region
    end

    # --- makes ---------------------------------------------------------------

    def test_makes_returns_strings
      makes = Vehicles.makes

      assert_operator makes.size, :>=, 40
      assert(makes.all?(String))
    end

    def test_makes_are_alphabetical
      assert_equal Vehicles.makes.sort_by(&:downcase), Vehicles.makes
    end

    def test_makes_include_well_known_brands
      %w[Volkswagen Audi BMW Toyota Renault Peugeot Tesla].each do |brand|
        assert_includes Vehicles.makes, brand
      end
    end

    def test_makes_filtered_by_kind_car
      assert_equal Vehicles.makes, Vehicles.makes(kind: :car)
    end

    def test_makes_filtered_by_unknown_kind_is_empty
      assert_empty Vehicles.makes(kind: :motorcycle)
    end

    def test_makes_for_unavailable_region_is_empty
      assert_empty Vehicles.makes(region: :us)
    end

    def test_makes_for_eu_region_is_full
      assert_equal Vehicles.makes, Vehicles.makes(region: :eu)
    end

    # --- models --------------------------------------------------------------

    def test_models_returns_names
      models = Vehicles.models("Volkswagen")

      assert_includes models, "Golf"
      assert_includes models, "Polo"
    end

    def test_models_is_case_insensitive
      assert_equal Vehicles.models("Audi"), Vehicles.models("audi")
      assert_equal Vehicles.models("Audi"), Vehicles.models("AUDI")
    end

    def test_models_resolves_builtin_alias
      assert_equal Vehicles.models("Volkswagen"), Vehicles.models("VW")
      assert_equal Vehicles.models("Mercedes-Benz"), Vehicles.models("merc")
    end

    def test_models_resolves_slug_and_diacritics
      assert_equal Vehicles.models("Alfa Romeo"), Vehicles.models("alfa-romeo")
      refute_empty Vehicles.models("Škoda")
      assert_equal Vehicles.models("Škoda"), Vehicles.models("skoda")
    end

    def test_models_for_unknown_make_is_empty
      assert_empty Vehicles.models("DeLorean")
      assert_empty Vehicles.models("")
      assert_empty Vehicles.models(nil)
    end

    def test_models_filtered_by_body_type
      suvs = Vehicles.models("Toyota", body_type: :suv)

      assert_includes suvs, "RAV4"
      refute_includes suvs, "Yaris"
    end

    def test_models_for_unavailable_region_is_empty
      assert_empty Vehicles.models("Audi", region: :us)
    end
  end
end
