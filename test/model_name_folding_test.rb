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

    def test_spacing_does_not_matter_xceed_is_x_ceed
      assert_equal "X Ceed", Vehicles.model("Kia", "XCeed")&.name
      assert_equal "X Ceed", Vehicles.model("Kia", "xceed")&.name
      assert_equal "Pro Ceed", Vehicles.model("Kia", "ProCeed")&.name
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
      assert_equal "Leon", Vehicles.model("SEAT", "  Leon ")&.name
    end

    def test_the_car_wins_when_a_name_is_several_kinds
      cruiser = Vehicles.model("Toyota", "Land Cruiser")

      assert_equal :car, cruiser.kind
      assert_equal :car, Vehicles.find("toyota land cruiser").kind
    end

    def test_kind_picks_another_kind
      assert_equal :bus, Vehicles.model("Toyota", "Land Cruiser", kind: :bus).kind
      assert_equal :van, Vehicles.make("Toyota").model("Land Cruiser", kind: "van").kind
      assert_nil Vehicles.model("SEAT", "Leon", kind: :motorcycle)
    end

    def test_a_name_with_no_car_keeps_the_first_kind
      assert_equal :moped, Vehicles.model("Aprilia", "Scarabeo").kind
    end
  end
end
