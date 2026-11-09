# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Vehicles
  # Vehicles.identify — the text entry point of the resolution contract
  # (RESOLUTION.md §3): canonical id, former id, longest make prefix + the
  # model ladder, whole-text alias, cleanup, typo.
  class IdentifyTest < TestCase
    FIXTURE = File.expand_path("fixtures/model_match/vehicles_forms_subset.json", __dir__)

    def setup
      Vehicles.data_path = FIXTURE
    end

    def test_make_prefix_then_the_model_ladder
      golf = Vehicles.identify("vw golf")

      assert_equal ["volkswagen-golf", :fold, 0.97, ["make_alias:vw→volkswagen"]],
                   [golf.model.slug, golf.rung, golf.confidence, golf.via]
      assert_equal(["ford-c-max", :form], Vehicles.identify("Ford Focus C-Max").then { |m| [m.model.slug, m.rung] })
      assert_equal "mercedes-benz-sprinter", Vehicles.identify("MERCEDES-BENZ | SPRINTER")&.model&.slug
    end

    def test_the_longest_make_prefix_wins
      Dir.mktmpdir do |dir|
        Vehicles.data_path = dataset(dir, { "name" => "Land", "models" => [model("Rover Defender")] },
                                     { "name" => "Land Rover", "models" => [model("Defender")] })

        assert_equal "land-rover-defender", Vehicles.identify("land rover defender")&.model&.slug
      end
    end

    def test_heuristics_on_the_model_part
      assert_equal([:fuzzy, ["make_alias:vw→volkswagen", "model_typo:tuareg→touareg"]],
                   Vehicles.identify("VW Tuareg").then { |m| [m.rung, m.via] })
      assert_equal :cleaned, Vehicles.identify("Citroën Nuevo Citroën C4")&.rung
    end

    def test_a_typo_corrected_make_is_fuzzy_and_never_stacks
      assert_equal([:fuzzy, 0.8], Vehicles.identify("volkswagon golf").then { |m| [m.rung, m.confidence] })
      assert_nil Vehicles.identify("volkswagon sirocco")
    end

    def test_nothing_resolves_without_a_make
      assert_nil Vehicles.identify("golf")
      assert_nil Vehicles.identify("Honda")
      assert_nil Vehicles.identify("")
      assert_nil Vehicles.identify(nil)
    end

    def test_canonical_id_and_former_id
      Dir.mktmpdir do |dir|
        Vehicles.data_path = dataset(dir, { "name" => "Alfa Romeo",
                                            "models" => [model("159", former_ids: ["car/alfa-romeo/159sw"])] })

        exact = Vehicles.identify("car/alfa-romeo/159")
        former = Vehicles.identify("car/alfa-romeo/159sw")

        assert_equal [:exact, 1.0], [exact.rung, exact.confidence]
        assert_equal ["alfa-romeo-159", :former_id, 0.98], [former.model.slug, former.rung, former.confidence]
        assert_nil Vehicles.identify("car/alfa-romeo/15")
      end
    end

    def test_whole_text_alias
      bmw = Vehicles.identify("1er")

      assert_equal ["bmw-1-series", :alias, 0.9], [bmw.model.slug, bmw.rung, bmw.confidence]
    end

    def test_whole_text_alias_never_beats_a_name_and_is_ambiguous_across_makes
      Dir.mktmpdir do |dir|
        Vehicles.data_path = dataset(dir,
                                     { "name" => "Aaa", "models" => [model("One", aliases: ["Zed"]),
                                                                     model("Two", aliases: ["Bee"])] },
                                     { "name" => "Bbb", "models" => [model("Bee"), model("Three", aliases: ["Zed"])] })

        assert_nil Vehicles.identify("bee"), "Bbb has a model NAMED Bee"
        assert_predicate Vehicles.identify("zed"), :ambiguous?
      end
    end

    def test_kind_hint
      bus = Vehicles.identify("Toyota Land Cruiser", kind: :bus)

      assert_equal [:bus, ["kind_hint:bus"]], [bus.model.kind, bus.via]
    end

    private

    def model(name, **extra)
      { "name" => name, "slug" => Vehicles.slugify(name), "kind" => "car" }.merge(extra.transform_keys(&:to_s))
    end

    def dataset(dir, *makes)
      path = File.join(dir, "vehicles.json")
      raw = makes.map { |mk| mk.merge("slug" => Vehicles.slugify(mk["name"]), "kinds" => ["car"]) }
      File.write(path, JSON.generate({ "version" => "test", "region" => "global", "makes" => raw }))
      path
    end
  end
end
