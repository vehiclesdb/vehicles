# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Model-name forms real users type that the dataset spells differently —
  # measured on a Spanish carpooling app's 1,329 free-text vehicles.
  class ModelNameFoldingTest < TestCase
    def test_spanish_serie_n_is_bmw_n_series
      assert_equal "1 Series", Vehicles.model("BMW", "Serie 1")&.name
      assert_equal "3 Series", Vehicles.model("BMW", "serie 3")&.name
      assert_equal "5 Series", Vehicles.model("bmw", "SERIE 5")&.name
      assert_equal "3 Series", Vehicles.find("BMW Serie 3")&.name
    end

    def test_a_real_serie_name_still_wins
      assert_equal "Serie X1", Vehicles.model("BMW", "Serie X1")&.name
    end

    def test_serie_needs_a_whole_series_name
      assert_nil Vehicles.model("BMW", "Serie")
      assert_nil Vehicles.model("BMW", "Serie 9")
    end

    # Data 2026.11.2 restyled Kia's "X Ceed"/"Pro Ceed" to "XCeed"/"ProCeed";
    # the spaced spellings must keep answering.
    def test_spacing_does_not_matter_xceed_is_x_ceed
      assert_equal "XCeed", Vehicles.model("Kia", "X Ceed")&.name
      assert_equal "XCeed", Vehicles.model("Kia", "xceed")&.name
      assert_equal "ProCeed", Vehicles.model("Kia", "Pro Ceed")&.name
    end

    def test_spaced_codes_join
      assert_equal "A5", Vehicles.model("Audi", "A 5")&.name
      assert_equal "X1", Vehicles.model("BMW", "X 1")&.name
    end

    def test_spacing_blindness_is_not_partial_matching
      assert_nil Vehicles.model("Kia", "X Cee")
      assert_nil Vehicles.model("Audi", "A")
    end

    def test_internal_double_spaces_collapse
      assert_equal "Model 3", Vehicles.model("Tesla", "Model  3")&.name
      assert_equal "León", Vehicles.model("SEAT", "  Leon ")&.name
    end

    # The one kind-collision rule (0.9.2; Vehicles::KindRule): lowest
    # mass_decile, then van > car > truck > bus > moped > motorcycle. Every
    # Land Cruiser record is decile 1, so the van answers; the car is one
    # `kind:` away.
    def test_the_collision_rule_picks_when_a_name_is_several_kinds
      assert_equal :van, Vehicles.model("Toyota", "Land Cruiser").kind
      assert_equal :van, Vehicles.find("toyota land cruiser").kind
      assert_equal :van, Vehicles.model("Iveco", "Daily").kind
      assert_equal :car, Vehicles.model("Mercedes-Benz", "V-Class").kind # car decile 1 beats van decile 2
      assert_equal :car, Vehicles.model("Toyota", "Land Cruiser", kind: :car).kind
    end

    def test_kind_picks_another_kind
      assert_equal :bus, Vehicles.model("Toyota", "Land Cruiser", kind: :bus).kind
      assert_equal :van, Vehicles.make("Toyota").model("Land Cruiser", kind: "van").kind
      assert_nil Vehicles.model("SEAT", "Leon", kind: :motorcycle)
    end

    def test_mass_decile_comes_before_the_kind_order
      # moped decile 6, motorcycle decile 2: the motorcycle is far more registered.
      assert_equal :motorcycle, Vehicles.model("Aprilia", "Scarabeo").kind
    end

    def test_kinds_is_a_hard_filter
      assert_nil Vehicles.model("Iveco", "Daily", kinds: %i[car])
      assert_equal :truck, Vehicles.model("Iveco", "Daily", kinds: %i[truck bus]).kind
      assert_nil Vehicles.model("Iveco", "Daily", kind: :van, kinds: %i[truck])
    end
  end
end
