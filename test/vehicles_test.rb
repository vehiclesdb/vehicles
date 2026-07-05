# frozen_string_literal: true

require "test_helper"

module Vehicles
  class VehiclesTest < TestCase
    # --- meta ----------------------------------------------------------------

    def test_data_version_is_present
      assert_match(/\A\d{4}\.\d{2}\.\d+\z/, Vehicles.data_version)
    end

    def test_region_is_global
      assert_equal :global, Vehicles.region
    end

    # --- makes ---------------------------------------------------------------

    def test_makes_returns_strings
      makes = Vehicles.makes

      assert_operator makes.size, :>=, 40
      assert(makes.all?(String))
    end

    def test_makes_are_alphabetical
      # Diacritic-insensitive order (normalize), so \u0160koda files under S,
      # not after Z the way a bare downcase sort would put it.
      assert_equal Vehicles.makes.sort_by { |n| Vehicles.normalize(n) }, Vehicles.makes
    end

    def test_makes_include_well_known_brands
      %w[Volkswagen Audi BMW Toyota Renault Peugeot Tesla].each do |brand|
        assert_includes Vehicles.makes, brand
      end
    end

    def test_makes_filtered_by_kind_car
      # Multi-kind data: car makes are a strict subset of all makes now.
      car_makes = Vehicles.makes(kind: :car)

      assert_operator car_makes.size, :>, 200
      assert_operator car_makes.size, :<, Vehicles.makes.size
      assert_includes car_makes, "Volkswagen"
    end

    def test_makes_filtered_by_absent_kind_is_empty
      # :plane is reserved in the schema but ships no data yet.
      assert_empty Vehicles.makes(kind: :plane)
    end

    def test_makes_filter_by_continent
      # region is a CONTINENT filter now; European makes are a subset of all.
      eu = Vehicles.makes(region: :eu)

      refute_empty eu
      assert_operator eu.size, :<=, Vehicles.makes.size
      assert_empty Vehicles.makes(region: :us) # country code, not a continent
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

    def test_models_filter_by_continent
      refute_empty Vehicles.models("Audi", region: :eu)
      assert_empty Vehicles.models("Audi", region: :us) # country, not continent
    end
  end
end
