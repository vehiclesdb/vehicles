# frozen_string_literal: true

require "test_helper"

module Vehicles
  # The 0.3.0 fields: continent regions, rarity tiers, and published aliases
  # (nicknames + native scripts).
  class RegionsRarityAliasesTest < TestCase
    def test_model_regions_and_continent_predicates
      golf = Vehicles.find("vw golf")

      assert_includes golf.regions, :eu
      assert_predicate golf, :european?
      assert golf.available_in_region?(:eu)
      refute golf.available_in_region?(:af)
    end

    def test_regions_enumerates_covered_continents
      assert_includes Vehicles.regions, :eu
      assert_includes Vehicles.regions, :as
      refute_includes Vehicles.regions, :zz
    end

    def test_rarity_tiers
      golf = Vehicles.find("vw golf")

      assert_includes %i[common average rare], golf.rarity
      assert_equal :common, Vehicles.find("toyota corolla").rarity
      # An unranked model reports :unknown, never a false tier.
      unranked = Vehicles.dataset.all_models.find { |m| m.global_decile.nil? }
      assert_equal :unknown, unranked.rarity if unranked
    end

    def test_rarity_filtering
      common = Vehicles.catalog_slice(kind: :car, rarity: :common)

      refute_empty common
      assert(common.all? { |m| m.global_decile && m.global_decile <= 3 })
      assert(Vehicles.catalog_slice(kind: :car, max_decile: 1).all? { |m| m.global_decile == 1 })
    end

    def test_make_aliases_published_and_resolve
      byd = Vehicles.make("BYD")

      assert_includes byd.aliases, "比亚迪"
      assert_equal byd, Vehicles.make("比亚迪") # native-script lookup
      assert_equal Vehicles.make("Chevrolet"), Vehicles.make("Chevy")
    end

    def test_model_aliases_published
      golf = Vehicles.find("vw golf")

      assert_includes golf.aliases, "Rabbit"
    end

    def test_make_continent_rollup
      byd = Vehicles.make("BYD")

      assert_includes byd.continents, :as
      assert byd.in_region?(:eu)
    end

    def test_continent_filtered_makes_are_a_subset
      all = Vehicles.makes(kind: :car)
      eu  = Vehicles.makes(kind: :car, region: :eu)

      assert_operator eu.size, :<=, all.size
      refute_empty eu
    end

    def test_top_models_by_continent
      asia = Vehicles.top_models(kind: :motorcycle, region: :as, limit: 5)

      refute_empty asia
      assert(asia.all? { |m| m.available_in_region?(:as) })
    end

    def test_to_h_includes_new_fields
      h = Vehicles.find("vw golf").to_h

      assert h.key?(:regions)
      assert h.key?(:rarity)
      assert h.key?(:aliases)
    end
  end
end
