# frozen_string_literal: true

require "test_helper"

module Vehicles
  # The 0.2.0 open-data fields: popularity deciles, availability evidence,
  # kind helpers, and the global-region behavior.
  class PopularityAvailabilityTest < TestCase
    def test_global_decile_on_a_global_icon
      golf = Vehicles.find("vw golf")

      assert_kind_of Integer, golf.global_decile
      assert_includes 1..3, golf.global_decile, "an icon must rank near the top"
      assert_predicate golf, :popular?
    end

    def test_availability_lists_iso_codes
      golf = Vehicles.find("vw golf")

      assert_includes golf.availability, "nl"
      assert_includes golf.availability, "gb"
      assert golf.available_in?(:nl)
      assert golf.available_in?("NL"), "case/symbol forgiving"
      refute golf.available_in?(:xx)
    end

    def test_unranked_models_are_honest
      # Catalog-only evidence (e.g. US-only approval) has no counts. Whatever
      # record we pick, nil decile must mean not-popular, never a crash.
      unranked = Vehicles.dataset.all_models.find { |m| m.global_decile.nil? }
      skip "dataset currently ranks every model" unless unranked

      refute_predicate unranked, :popular?, "unknown must never read as popular"
      assert_equal [], unranked.availability & ["zz"]
    end

    def test_kinds_reflect_the_snapshot
      assert_includes Vehicles.kinds, :car
      assert_includes Vehicles.kinds, :motorcycle
      assert_includes Vehicles.kinds, :moped
    end

    def test_top_models_ranking_and_filters
      top = Vehicles.top_models(kind: :car, limit: 5)

      assert_equal 5, top.size
      assert(top.all? { |m| m.kind == :car })
      assert top.all? { |m| m.global_decile == 1 }, "the top of the list is decile 1"

      nl = Vehicles.top_models(kind: :car, country: :nl, limit: 5)

      assert(nl.all? { |m| m.available_in?(:nl) })
    end

    def test_top_models_never_surfaces_unranked_records
      assert Vehicles.top_models(limit: 100).all?(&:global_decile)
    end

    def test_two_wheeler_union_helper
      moto = Vehicles.dataset.all_models.find { |m| m.kind == :motorcycle }
      car  = Vehicles.find("vw golf")

      assert_predicate moto, :two_wheeler?
      refute_predicate car, :two_wheeler?
    end

    def test_non_car_kinds_have_no_phantom_body_type
      # The 2026-07 audit found trucks wearing "hatchback"; the fix ships nil.
      moto = Vehicles.dataset.all_models.find { |m| m.kind == :motorcycle }

      assert_nil moto.body_type
      refute_predicate moto, :hatchback?
    end

    def test_global_region_covers_every_region_query
      assert Vehicles.dataset.region?(:eu), "a global snapshot must keep region: :eu callers working"
      assert_operator Vehicles.models("BMW", region: :eu).size, :>, 0
    end
  end
end
