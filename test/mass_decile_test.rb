# frozen_string_literal: true

require "test_helper"

module Vehicles
  # 0.7.8: Model#mass_decile (popularity.mass_decile, data 2026.10.1+, pipeline#255 / ruling R3)
  # and top_models(by: :mass_decile). Nil-safe on snapshots that predate the key.
  class MassDecileTest < TestCase
    def mass_raw
      { "version" => "t", "makes" => [
        { "name" => "A", "slug" => "a", "kinds" => ["car"], "models" => [
          { "name" => "Everywhere", "slug" => "everywhere", "kind" => "car", "global_decile" => 1,
            "mass_decile" => 4, "availability" => %w[gb nl] },
          { "name" => "Heavy", "slug" => "heavy", "kind" => "car", "global_decile" => 3,
            "mass_decile" => 1, "availability" => ["gb"] },
          { "name" => "Unranked", "slug" => "unranked", "kind" => "car", "availability" => ["gb"] }
        ] }
      ] }
    end

    def test_mass_decile_is_nil_safe_on_the_bundled_snapshot
      golf = Vehicles.find("vw golf")

      assert_nil golf.mass_decile, "2026.10.0 predates popularity.mass_decile"
      assert_equal [], Vehicles.top_models(kind: :car, by: :mass_decile), "no mass ranks yet → honestly empty"
      refute_empty Vehicles.top_models(kind: :car)
    end

    def test_mass_decile_is_read_and_orders_by_mass
      ds = Dataset.new(mass_raw)

      assert_equal 1, ds.all_models.find { |m| m.name == "Heavy" }.mass_decile
      assert_equal %w[Everywhere Heavy], ds.top_models.map(&:name), "default stays global_decile"
      assert_equal %w[Heavy Everywhere], ds.top_models(by: :mass_decile).map(&:name)
      refute_includes ds.top_models(by: :mass_decile).map(&:name), "Unranked"
    end

    def test_mass_decile_reads_the_catalog_shape_too
      m = Model.new({ "name" => "X", "slug" => "x", "popularity" => { "mass_decile" => 2 } }, make: "A", make_slug: "a")

      assert_equal 2, m.mass_decile
    end

    def test_a_non_hash_popularity_never_raises
      attrs = { "name" => "X", "slug" => "x", "popularity" => "n/a" }

      assert_nil Model.new(attrs, make: "A", make_slug: "a").mass_decile
    end

    def test_unknown_ranking_raises
      assert_raises(ArgumentError) { Vehicles.top_models(by: :popularity) }
    end
  end
end
