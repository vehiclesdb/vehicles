# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module Vehicles
  # Canonical ids (0.9.2): Model#id, id-based equality, Vehicles.by_id /
  # successor / live?, make former_slugs.
  class IdsTest < TestCase
    def test_model_id_is_kind_make_model
      assert_equal "car/volkswagen/golf", Vehicles.find("vw golf").id
      assert_predicate Vehicles.find("vw golf").id, :frozen?
      assert_equal "car/volkswagen/golf", Vehicles.find("vw golf").to_h[:id]
    end

    # Until 0.9.1 == compared the composite slug: the van and the bus Daily
    # were "equal" and collapsed in sets and hash keys.
    def test_kind_variants_are_different_records
      van = Vehicles.model("Iveco", "Daily", kind: :van)
      bus = Vehicles.model("Iveco", "Daily", kind: :bus)

      assert_equal van.slug, bus.slug
      refute_equal van, bus
      assert_equal 2, [van, bus].uniq.size
      by_record = { van => 1, bus => 2 }

      assert_equal 2, by_record.size
      assert_equal van, Vehicles.by_id(van.id)
    end

    def test_by_id_follows_former_ids_unless_told_not_to
      retired = renamed_record
      old_id = retired.former_ids.first

      assert_equal retired, Vehicles.by_id(old_id)
      assert_nil Vehicles.by_id(old_id, follow: false)
      assert_equal retired.id, Vehicles.successor(old_id)
      assert_equal retired.id, Vehicles.successor(retired.id)
      refute Vehicles.live?(old_id)
      assert Vehicles.live?(retired.id)
    end

    def test_unknown_ids
      assert_nil Vehicles.by_id("car/nope/nope")
      assert_nil Vehicles.successor("car/nope/nope")
      assert_nil Vehicles.by_id("")
      refute Vehicles.live?(nil)
    end

    def test_an_id_two_records_absorbed_has_no_successor
      with_dataset({ "Testa" => [model("one", former: ["car/testa/old"]), model("two", former: ["car/testa/old"])] }) do
        assert_nil Vehicles.by_id("car/testa/old")
      end
    end

    # Make former_slugs: no-op until the dataset publishes them, then
    # Vehicles.make and Vehicles.by_id follow a renamed make.
    def test_make_former_slugs_are_followed_when_published
      with_dataset({ "Newco" => [model("roadster", former: ["car/oldco/speedster"])] },
                   former_slugs: { "Newco" => ["oldco"] }) do
        assert_equal "Newco", Vehicles.make("oldco", fuzzy: false).name
        assert_equal "car/newco/roadster", Vehicles.by_id("car/oldco/roadster")&.id  # same model slug, new make
        assert_equal "car/newco/roadster", Vehicles.by_id("car/oldco/speedster")&.id # former id
        assert_includes Vehicles.match_model("Oldco", "Roadster").via, "former_make_slug:oldco→newco"
      end
    end

    def test_identify_answers_the_same_record_for_an_id
      daily = Vehicles.model("Iveco", "Daily", kind: :bus)

      assert_equal daily, Vehicles.identify(daily.id).model
      assert_equal daily, Vehicles.identify(daily.id, kind: :car).model # an id is explicit
      assert_nil Vehicles.identify(daily.id, kinds: %i[car]) # kinds: is a hard filter
    end

    private

    def renamed_record
      Vehicles.dataset.all_models.find { |m| m.former_ids.any? && Vehicles.by_id(m.former_ids.first) == m }
    end

    def model(slug, former: [])
      { "name" => slug.capitalize, "slug" => slug, "kind" => "car", "former_ids" => former }
    end

    def with_dataset(makes, former_slugs: {})
      Dir.mktmpdir do |dir|
        path = File.join(dir, "v.json")
        raw = makes.map do |name, models|
          { "name" => name, "slug" => Vehicles.slugify(name), "kinds" => ["car"], "models" => models,
            "former_slugs" => former_slugs[name] || [] }
        end
        File.write(path, JSON.generate("version" => "1.0.0", "schema_version" => 2, "makes" => raw))
        Vehicles.data_path = path
        yield
      end
    end
  end
end
