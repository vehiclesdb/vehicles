# frozen_string_literal: true

require "test_helper"

module Vehicles
  class CatalogTest < TestCase
    def test_catalog_maps_make_names_to_model_names
      catalog = Vehicles.catalog

      assert_kind_of Hash, catalog
      assert_includes catalog.keys, "Volkswagen"
      assert_includes catalog["Volkswagen"], "Golf"
      assert(catalog.values.all?(Array))
    end

    def test_catalog_keys_match_makes
      assert_equal Vehicles.makes, Vehicles.catalog.keys
    end

    def test_catalog_values_match_models
      assert_equal Vehicles.models("Audi"), Vehicles.catalog["Audi"]
    end

    def test_catalog_respects_kind_filter
      assert_equal Vehicles.makes(kind: :car), Vehicles.catalog(kind: :car).keys
      assert_empty Vehicles.catalog(kind: :motorcycle)
    end

    def test_catalog_respects_region_filter
      assert_empty Vehicles.catalog(region: :us)
      refute_empty Vehicles.catalog(region: :eu)
    end

    def test_catalog_is_json_ready
      json = Vehicles.catalog.to_json
      round_tripped = JSON.parse(json)

      assert_equal Vehicles.models("SEAT"), round_tripped["SEAT"]
    end
  end
end
