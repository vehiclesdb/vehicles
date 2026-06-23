# frozen_string_literal: true

require "test_helper"

module Vehicles
  class LookupTest < TestCase
    # --- find ----------------------------------------------------------------

    def test_find_resolves_make_and_model
      car = Vehicles.find("vw golf")

      assert_instance_of Vehicles::Model, car
      assert_equal "Volkswagen Golf", car.full_name
    end

    def test_find_handles_multi_word_models
      car = Vehicles.find("Mercedes C Class")

      assert_equal "Mercedes-Benz C-Class", car.full_name
    end

    def test_find_handles_multi_word_makes
      car = Vehicles.find("land rover defender")

      assert_equal "Land Rover Defender", car.full_name
    end

    def test_find_is_case_and_alias_insensitive
      assert_equal Vehicles.find("VW GOLF"), Vehicles.find("volkswagen golf")
    end

    def test_find_returns_nil_for_garbage
      assert_nil Vehicles.find("nope nope")
      assert_nil Vehicles.find("golf") # make alone is not a make+model
      assert_nil Vehicles.find("")
      assert_nil Vehicles.find("   ")
    end

    def test_find_returns_nil_for_unknown_model_of_known_make
      assert_nil Vehicles.find("audi mustang")
    end

    # --- model(make, model) — structured pair lookup -------------------------

    def test_model_resolves_a_stored_make_model_pair
      car = Vehicles.model("Audi", "A3")

      assert_instance_of Vehicles::Model, car
      assert_equal "Audi A3", car.full_name
      assert_equal :hatchback, car.body_type
    end

    def test_model_pair_is_forgiving
      assert_equal Vehicles.model("Volkswagen", "Golf"), Vehicles.model("vw", "golf")
    end

    def test_model_pair_returns_nil_for_unknown
      assert_nil Vehicles.model("Audi", "Mustang")
      assert_nil Vehicles.model("Nope", "Golf")
      assert_nil Vehicles.model("Audi", "")
      assert_nil Vehicles.model(nil, nil)
    end

    # --- search --------------------------------------------------------------

    def test_search_finds_by_model_name
      results = Vehicles.search("golf")

      assert_includes results.map(&:full_name), "Volkswagen Golf"
    end

    def test_search_is_ranked_exact_first
      # "Leon" is built by both Cupra and SEAT — an exact name match must rank
      # ahead of substring matches like "Leon"-in-something-else.
      results = Vehicles.search("leon")

      assert_equal "Leon", results.first.name
      assert_includes results.map(&:full_name), "SEAT Leon"
      assert_includes results.map(&:full_name), "Cupra Leon"
    end

    def test_search_returns_models
      assert(Vehicles.search("corolla").all?(Vehicles::Model))
    end

    def test_search_substring_matches
      results = Vehicles.search("ioniq")

      assert_operator results.size, :>=, 2
      assert(results.all? { |m| m.name.downcase.include?("ioniq") })
    end

    def test_search_empty_query_returns_empty
      assert_empty Vehicles.search("")
      assert_empty Vehicles.search("   ")
    end

    def test_search_no_match_returns_empty
      assert_empty Vehicles.search("zzzzzz")
    end

    def test_search_matches_full_name
      results = Vehicles.search("volkswagen golf")

      assert_includes results.map(&:full_name), "Volkswagen Golf"
    end
  end
end
