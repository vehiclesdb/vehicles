# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Vehicles
  # 0.9.0: Vehicles.model also answers published aliases and curated registry
  # spellings (Model#forms); Vehicles.match_model adds cleanup and typo rungs
  # and says HOW it matched. The one rule: never a confident wrong answer.
  #
  # Runs on a committed subset of a dataset release that carries `forms`
  # (23 makes, every model kept so neighbours, ties and kinds are real), so
  # the expectations do not move when the bundled snapshot is refreshed.
  class ModelMatchTestCase < TestCase
    FIXTURE = File.expand_path("fixtures/model_match/vehicles_forms_subset.json", __dir__)

    def setup
      Vehicles.data_path = FIXTURE
    end

    private

    def id(model)
      model && "#{model.kind}/#{model.make_slug}/#{model.model_slug}"
    end

    # A minimal dataset file: { "Make" => [[name, slug, extra attrs], ...] }.
    def write_dataset(dir, makes)
      path = File.join(dir, "vehicles.json")
      raw = makes.map do |name, models|
        { "name" => name, "slug" => Vehicles.slugify(name), "kinds" => ["car"],
          "models" => models.map { |n, s, extra| { "name" => n, "slug" => s, "kind" => "car" }.merge(extra || {}) } }
      end
      File.write(path, JSON.generate({ "version" => "test", "region" => "global", "makes" => raw }))
      path
    end
  end

  class ModelMatchCarheyTest < ModelMatchTestCase
    # --- CarHey acceptance ---------------------------------------------------
    # Every typed make|model pair the CarHey app failed to resolve with 0.8.0
    # (dogfooding, 2026-11). Each must resolve to the right record or abstain
    # where abstaining is the right answer.

    CARHEY = {
      ["Peugeot", "2008 Allure"] => "car/peugeot/2008",
      ["Peugeot", "208 5P Style"] => "car/peugeot/208",
      ["Hyundai", "Tucson IX35"] => "car/hyundai/ix35",
      ["SEAT", "Leon Sc"] => "car/seat/leon",
      ["Saab", "9-3 Aero"] => "car/saab/9-3",
      ["Renault", "Megane Sport"] => "car/renault/megane",
      ["Volkswagen", "Polo 1"] => "car/volkswagen/polo",
      ["Peugeot", "208 5P Allure"] => "car/peugeot/208",
      ["Opel", "Corsa  E"] => "car/opel/corsa",
      ["Volkswagen", "Passat GT"] => "car/volkswagen/passat",
      ["Nissan", "Qashqai +2"] => "car/nissan/qashqai",
      %w[Opel Insigna] => "car/opel/insignia",
      ["Omoda", "OMODA5 Hev"] => "car/omoda/omoda-5",
      %w[Mercedes-Benz Marco] => "car/mercedes-benz/marco-polo",
      ["Lexus", "IS 300H"] => "car/lexus/is",
      ["Peugeot", "307 1.6I"] => "car/peugeot/307",
      ["Hyundai", "Kona Kauai"] => "car/hyundai/kona",
      ["Peugeot", "308 1.6I"] => "car/peugeot/308",
      ["Ebro", "S400 Hev"] => "car/ebro/s400",
      %w[Volkswagen Newbeetle] => "car/volkswagen/beetle",
      ["Škoda", "Fabia Combi"] => "car/skoda/fabia",
      ["Ford", "Focus C-Max"] => "car/ford/c-max",
      ["Škoda", "Octavia A7"] => "car/skoda/octavia",
      ["Peugeot", "308 1.2I Stt"] => "car/peugeot/308",
      ["Nissan", "Qashqai N-Tec"] => "car/nissan/qashqai",
      ["SEAT", "Ibiza Cupra"] => "car/seat/ibiza",
      ["Renault", "Megane Conquest"] => "car/renault/arkana", # not the Megane
      ["Austin-Healey", "Healey Sprite"] => "car/austin-healey/sprite",
      ["Maserati", "Grecale Modena"] => "car/maserati/grecale",
      %w[Volkswagen GTI] => "car/volkswagen/golf", # only because it is a curated form
      %w[Lexus UX250H] => "car/lexus/ux",
      ["Citroën", "Nuevo Citroën C3 Aircr"] => "car/citroen/c3-aircross", # not the C3
      ["Lynk & Co", "Lynk And Co 01"] => "car/lynk-co/01",
      ["Citroën", "Nuevo C4"] => "car/citroen/c4",
      %w[Volkswagen Toureg] => "car/volkswagen/touareg",
      ["Kia", "Sportage SL"] => "car/kia/sportage",
      # Only match_model (typo rung) — not curated, so Vehicles.model abstains.
      %w[Volkswagen Sirocco] => "car/volkswagen/scirocco",
      # Correct abstentions: a make, not a model; an engine code; no such make.
      %w[Honda Honda] => nil,
      %w[Nissan Nissan] => nil,
      %w[Mercedes-Benz Cdi] => nil,
      %w[Abt Xgt] => nil
    }.freeze

    def test_carhey_typed_misses_resolve_or_abstain_correctly
      CARHEY.each do |(make, model), want|
        got = Vehicles.match_model(make, model)

        if want
          assert_equal want, id(got&.model), "match_model(#{make.inspect}, #{model.inspect})"
        else
          assert_nil got, "match_model(#{make.inspect}, #{model.inspect}) must abstain"
        end
      end
    end

    def test_carhey_curated_pairs_resolve_through_vehicles_model
      CARHEY.each do |(make, model), want|
        got = id(Vehicles.model(make, model))
        if want && model != "Sirocco" # Sirocco is the typo rung: match_model only
          assert_equal want, got, "model(#{make.inspect}, #{model.inspect})"
        else
          assert_nil got, "model(#{make.inspect}, #{model.inspect})"
        end
      end
    end
  end

  # The ladder, rung by rung: what each answers and what it reports.
  class ModelMatchLadderTest < ModelMatchTestCase
    def test_strict_name_is_rung_a
      m = Vehicles.match_model("Peugeot", "2008")

      assert_equal [:name, 1.0, ["name:2008"]], [m.method, m.confidence, m.via]
      refute_predicate m, :ambiguous?
    end

    def test_spacing_and_series_are_name_matches_with_a_lower_label
      xceed = Vehicles.match_model("Kia", "XCeed")
      serie = Vehicles.match_model("BMW", "Serie 3")

      assert_equal ["X Ceed", :name, 0.97], [xceed.model.name, xceed.method, xceed.confidence]
      assert_equal ["spacing:xceed→x-ceed"], xceed.via
      assert_equal ["3 Series", ["series:serie 3→3-series"]], [serie.model.name, serie.via]
    end

    def test_published_alias
      m = Vehicles.match_model("Nissan", "Qashqai +2")

      assert_equal ["car/nissan/qashqai", :alias, 0.93], [id(m.model), m.method, m.confidence]
      assert_equal ["alias:qashqai 2→qashqai"], m.via
    end

    def test_curated_form
      m = Vehicles.match_model("Ford", "Focus C-Max")

      assert_equal ["car/ford/c-max", :form, 0.92], [id(m.model), m.method, m.confidence]
      assert_equal ["form:focus c max→c-max"], m.via
      assert_includes m.model.forms, "Focus C-Max"
    end

    def test_cleanup_peels_fillers_and_echoed_make_names
      golf = Vehicles.match_model("VW", "Nuevo Golf")
      c4 = Vehicles.match_model("Citroën", "Nuevo Citroën C4")

      assert_equal ["car/volkswagen/golf", :cleaned, 0.9], [id(golf.model), golf.method, golf.confidence]
      assert_equal ["make_alias:vw→volkswagen", "filler:nuevo", "name:golf"], golf.via
      assert_equal ["filler:nuevo", "make_echo:citroen", "name:c4"], c4.via
    end

    def test_cleanup_reads_ampersand_as_and
      # Bare names only (the fixture's curated forms would answer first).
      assert_equal ["make_echo:lynk and co"], ModelMatcher.peel(Vehicles.make("Lynk & Co"), "lynk and co 01",
                                                                "Lynk & Co", false).drop(1)
    end

    def test_cleanup_that_leaves_nothing_is_nil
      assert_nil Vehicles.match_model("Honda", "Honda")
      assert_nil Vehicles.match_model("Lexus", "Lexus")
      assert_nil Vehicles.match_model("Citroën", "Nuevo Citroën")
    end

    def test_cleanup_never_peels_a_partial_make_name
      # "Healey" is part of "Austin-Healey", not the make: only a curated form
      # may say "Healey Sprite" is the Sprite.
      assert_nil Vehicles.match_model("Austin-Healey", "Healey")
    end

    def test_cleanup_never_peels_a_word_that_is_a_model_name
      # Chevrolet sells a "Nova": "Nova Sedan" is not a "new Sedan".
      refute_nil Vehicles.make("Chevrolet").model("Nova"), "fixture: Nova is a Chevrolet"
      assert_nil Vehicles.match_model("Chevrolet", "Nova Sedan")
    end

    def test_typo
      [%w[Volkswagen Sirocco car/volkswagen/scirocco], %w[Volkswagen Tuareg car/volkswagen/touareg],
       %w[Opel Insignai car/opel/insignia], %w[Ford Mustnag car/ford/mustang]].each do |make, model, want|
        m = Vehicles.match_model(make, model)

        assert_equal [want, :typo, 0.8], [id(m&.model), m&.method, m&.confidence], "#{make} #{model}"
      end
      assert_equal ["typo:sirocco→scirocco"], Vehicles.match_model("Volkswagen", "Sirocco").via
    end
  end

  # Never a confident wrong answer: abstentions, ambiguity, kinds, and the
  # strict surfaces (Make#model, the validator) left exactly as they were.
  class ModelMatchSafetyTest < ModelMatchTestCase
    def test_numeric_near_neighbours_never_typo
      assert_nil Vehicles.match_model("Peugeot", "2009")
      assert_nil Vehicles.match_model("Peugeot", "3080")
      assert_equal "car/peugeot/2008", id(Vehicles.match_model("Peugeot", "2008").model)
      assert_equal "car/peugeot/208", id(Vehicles.match_model("Peugeot", "208").model)
      # Code tokens are identical or nothing: TRX (an ATV) is not TLR (trials).
      assert_nil Vehicles.match_model("Honda", "TRX250R")
      assert_nil Vehicles.match_model("Honda", "XR200A")
    end

    def test_short_tokens_and_codes_never_typo
      assert_nil Vehicles.match_model("Mercedes-Benz", "Cdi")
      refute_equal "Passat GL", Vehicles.match_model("Volkswagen", "Passat GT")&.model&.name
    end

    def test_two_edit_typos_need_a_long_word
      # Two edits apart, all real and different cars (bench findings).
      Dir.mktmpdir do |dir|
        Vehicles.data_path = write_dataset(dir, "Lotus" => [%w[Elise elise]], "Jeep" => [%w[Commander commander]])

        assert_nil Vehicles.match_model("Lotus", "Exige")
        assert_nil Vehicles.match_model("Jeep", "Commando")
      end
    end

    def test_partial_input_stays_nil
      assert_nil Vehicles.match_model("Volkswagen", "G")
      assert_nil Vehicles.match_model("Ford", "Fo")
      assert_nil Vehicles.match_model("Ford", "Musta")
      assert_nil Vehicles.model("Volkswagen", "G")
    end

    def test_a_typo_tie_is_ambiguous
      m = Vehicles.match_model("Toyota", "Corola")

      assert_predicate m, :ambiguous?
      assert_nil m.model
      assert_in_delta 0.0, m.confidence
      assert_equal %w[corolla corona], m.candidates.map(&:model_slug).uniq.sort
      assert_nil Vehicles.model("Toyota", "Corola")
    end

    def test_no_typo_on_top_of_a_typo_corrected_make
      assert_equal "volkswagen", Vehicles.make("Volkswagon")&.slug
      assert_nil Vehicles.match_model("Volkswagon", "Sirocco")
    end

    def test_a_typo_corrected_make_caps_the_confidence
      m = Vehicles.match_model("Volkswagon", "Golf")

      assert_equal ["car/volkswagen/golf", :name, 0.8], [id(m.model), m.method, m.confidence]
      assert_equal ["make_typo:volkswagon→volkswagen", "name:golf"], m.via
    end

    def test_id_shaped_input_never_takes_the_heuristic_rungs
      ["car/volkswagen/sirocco", :sirocco, "sirocco-x", "nuevo-golf", "nuevo_golf"].each do |q|
        assert_nil Vehicles.match_model("Volkswagen", q), "#{q.inspect} must not fuzz or clean"
      end
      assert_equal "car/ford/c-max", id(Vehicles.match_model("Ford", "c-max").model), "an exact slug still resolves"
    end

    def test_ambiguity_stops_the_ladder
      # "Nuevo Gamma" is curated on two different models. Peeling "nuevo"
      # would reach the real "Gamma" — a weaker rung must never overrule
      # the data saying "this could be either".
      Dir.mktmpdir do |dir|
        Vehicles.data_path = write_dataset(dir, "Testa" => [
                                             ["Alpha", "alpha", { "forms" => ["Nuevo Gamma"] }],
                                             ["Beta", "beta", { "forms" => ["Nuevo Gamma"] }],
                                             %w[Gamma gamma]
                                           ])
        m = Vehicles.match_model("Testa", "Nuevo Gamma")

        assert_predicate m, :ambiguous?
        assert_equal [:form, %w[alpha beta]], [m.method, m.candidates.map(&:model_slug).sort]
        assert_nil Vehicles.model("Testa", "Nuevo Gamma")
      end
      Dir.mktmpdir do |dir| # sanity: without the collision, cleanup does reach Gamma
        Vehicles.data_path = write_dataset(dir, "Testa" => [%w[Alpha alpha], %w[Gamma gamma]])

        assert_equal "gamma", Vehicles.match_model("Testa", "Nuevo Gamma")&.model&.model_slug
      end
    end

    def test_a_spacing_blind_collision_is_ambiguous_not_a_pick
      Dir.mktmpdir do |dir|
        Vehicles.data_path = write_dataset(dir, "Testa" => [["AB C", "ab-c"], ["A BC", "a-bc"]])

        assert_predicate Vehicles.match_model("Testa", "ABC"), :ambiguous?
        assert_nil Vehicles.model("Testa", "ABC")
        assert_nil Vehicles.make("Testa").model("ABC")
      end
    end

    # --- kinds ---------------------------------------------------------------

    def test_the_car_is_preferred_and_candidates_carry_every_kind
      m = Vehicles.match_model("Toyota", "Land Cruiser")

      assert_equal :car, m.model.kind
      assert_equal %i[bus car truck van], m.candidates.map(&:kind).sort
    end

    def test_kind_is_honoured
      m = Vehicles.match_model("Toyota", "Land Cruiser", kind: :bus)

      assert_equal [:bus, [:bus]], [m.model.kind, m.candidates.map(&:kind)]
      assert_equal :bus, Vehicles.model("Toyota", "Land Cruiser", kind: :bus).kind
      assert_nil Vehicles.match_model("Opel", "Insignai", kind: :bus)
    end

    # --- Make#model and the validator are unchanged ---------------------------

    def test_make_model_stays_strict
      vw = Vehicles.make("Volkswagen")

      assert_nil vw.model("GTI"), "a curated form is not a name"
      assert_nil vw.model("Sirocco")
      assert_nil vw.model("a")
      assert_equal "Golf", vw.model("golf").name
    end

    def test_make_model_answers_exactly_as_the_old_linear_scan
      # Make#model moved onto memoized indexes in 0.9.0 (it normalized every
      # model name on every call). Replay the 0.8.0 algorithm over the whole
      # bundled snapshot: same answer, same kind, for every name, squeezed
      # name and "Serie N" query.
      Vehicles.data_path = nil
      Vehicles.dataset.makes.each do |make|
        # By identity: Model#== compares slugs, so kind variants would collide.
        names = make.models.each_with_object({}.compare_by_identity) { |m, h| h[m] = Vehicles.normalize(m.name) }
        make.models.each do |model|
          name = names[model]
          [name, name.delete(" "), "serie #{name}"].uniq.each do |q|
            want = legacy_scan(make.models, names, q)

            got = make.model(q)
            want ? assert_same(want, got, "#{make.name} #{q.inspect}") : assert_nil(got, "#{make.name} #{q.inspect}")
          end
        end
      end
    end

    def test_the_validator_does_not_accept_forms_or_typos
      skip "ActiveModel not available" unless defined?(ActiveModel::EachValidator)

      car = Class.new do
        include ActiveModel::Model

        attr_accessor :make, :model

        validates :model, vehicle_model: { make: :make }
        def self.model_name = ActiveModel::Name.new(self, nil, "Car")
      end

      refute_predicate car.new(make: "Volkswagen", model: "GTI"), :valid?
      refute_predicate car.new(make: "Volkswagen", model: "Sirocco"), :valid?
      assert_predicate car.new(make: "Volkswagen", model: "Golf"), :valid?
    end

    # --- ModelMatch ----------------------------------------------------------

    def test_model_match_is_an_immutable_value
      m = Vehicles.match_model("Ford", "Focus C-Max")

      assert_predicate m, :frozen?
      assert_predicate m.via, :frozen?
      assert_predicate m.candidates, :frozen?
      assert_equal m, Vehicles.match_model("Ford", "Focus C-Max")
      assert_equal ["ford-c-max", :form, false], [m.to_h[:model][:slug], m.to_h[:method], m.to_h[:ambiguous]]
      assert_match(/Ford C-Max/, m.inspect)
    end

    def test_nothing_at_all_is_nil
      assert_nil Vehicles.match_model("Zzyzx Motors", "Golf")
      assert_nil Vehicles.match_model("Volkswagen", "")
      assert_nil Vehicles.match_model("Volkswagen", nil)
      assert_nil Vehicles.match_model("Volkswagen", "Qqqqqqqq")
    end

    def test_model_forms_default_to_empty_and_frozen
      model = Model.new({ "name" => "X", "slug" => "x" }, make: "M", make_slug: "m")

      assert_equal [], model.forms
      assert_predicate model.forms, :frozen?
    end

    private

    # Make#model as shipped in 0.8.0 (a linear scan), for the equivalence test.
    def legacy_scan(pool, names, query)
      named = lambda do |q|
        exact = pool.select { |m| names[m] == q || m.model_slug == q }
        next exact if exact.any?

        loose = pool.select { |m| names[m].delete(" ") == q.delete(" ") }
        loose if loose.map { |m| names[m] }.uniq.one?
      end
      series = query.sub(Make::LOCALIZED_SERIES, '\\1 series')
      matches = named.call(query) || (named.call(series) unless series == query)
      matches && (matches.find(&:car?) || matches.first)
    end
  end
end
