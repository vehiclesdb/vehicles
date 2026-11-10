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
      refute_empty Vehicles.catalog(kind: :motorcycle)   # bikes ship since 0.2.0
      assert_empty Vehicles.catalog(kind: :plane)        # reserved, no data yet
    end

    def test_catalog_respects_region_filter
      # region is a CONTINENT filter (:eu/:na/:as/...); a country code or an
      # unmapped continent honestly returns nothing.
      refute_empty Vehicles.catalog(region: :eu)
      refute_empty Vehicles.catalog(region: :as)
      assert_empty Vehicles.catalog(region: :us) # :us is a country, not a continent
    end

    # The per-country picker list (0.9.2): CarHey built it from
    # top_models(country: "es", limit: 10_000).group_by(&:make).
    def test_catalog_scopes_to_a_country
      es = Vehicles.catalog(kind: :car, country: :es)

      assert_equal es.keys.sort_by { |n| Vehicles.normalize(n) }, es.keys # alphabetical makes
      assert(es.values.flatten.size.between?(1000, 2000))
      assert_operator es.size, :<, Vehicles.catalog(kind: :car).size
      seat = Vehicles.make("SEAT").models(kind: :car, country: :es)

      assert_equal seat.map(&:name), es["SEAT"]
      assert(seat.each_cons(2).all? { |a, b| a.rank_in(:es) <= b.rank_in(:es) }, "Spain's own order")
    end

    def test_every_model_in_a_country_catalog_is_evidenced_there
      es = Vehicles.catalog(kind: :car, country: :es)

      assert(es.all? { |make, names| names.all? { |n| Vehicles.model(make, n, kind: :car).available_in?(:es) } })
    end

    def test_catalog_country_equals_the_old_top_models_workaround
      grouped = Vehicles.top_models(kind: :car, country: :es, limit: nil).group_by(&:make)
                        .transform_values { |ms| ms.map(&:name) }

      assert_equal grouped.keys.sort, Vehicles.catalog(kind: :car, country: :es).keys.sort
      assert_equal grouped["SEAT"], Vehicles.catalog(kind: :car, country: :es)["SEAT"]
    end

    def test_country_filters_makes_models_and_options
      assert_includes Vehicles.makes(kind: :car, country: :es), "SEAT"
      refute_includes Vehicles.makes(kind: :car, country: :es), "Perodua"
      assert_equal Vehicles.catalog(kind: :car, country: :es)["SEAT"],
                   Vehicles.models("SEAT", kind: :car, country: "ES")
      assert_equal Vehicles.models("SEAT", kind: :car, country: :es),
                   Vehicles.model_options("SEAT", kind: :car, country: :es).map(&:first)
      assert_includes Vehicles.make_options(kind: :car, country: :es), %w[SEAT seat]
      assert_empty Vehicles.catalog(kind: :car, country: :zz)
    end

    def test_catalog_takes_kinds
      both = Vehicles.catalog(kinds: %i[car van], country: :es)

      assert_includes both["Volkswagen"], "Caddy"
      assert_equal both["Volkswagen"], both["Volkswagen"].uniq
      assert_empty Vehicles.catalog(kinds: [])
      assert_equal Vehicles.catalog(kind: :car, country: :es), Vehicles.catalog(kinds: [:car], country: :es)
    end

    def test_catalog_is_json_ready
      json = Vehicles.catalog.to_json
      round_tripped = JSON.parse(json)

      assert_equal Vehicles.models("SEAT"), round_tripped["SEAT"]
    end
  end
end
