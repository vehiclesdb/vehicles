# frozen_string_literal: true

require "test_helper"

module Vehicles
  class ModelTest < TestCase
    def setup
      @golf   = Vehicles.find("vw golf")
      @tiguan = Vehicles.find("vw tiguan")
    end

    def test_basic_attributes
      assert_equal "Volkswagen", @golf.make
      assert_equal "Golf", @golf.name
      assert_equal "Volkswagen Golf", @golf.full_name
      assert_equal "volkswagen-golf", @golf.slug
      assert_equal "golf", @golf.model_slug
    end

    def test_to_s_is_full_name
      assert_equal "Volkswagen Golf", @golf.to_s
    end

    def test_kind_and_body_type_are_symbols
      assert_equal :car, @golf.kind
      assert_equal :hatchback, @golf.body_type
      assert_equal :suv, @tiguan.body_type
    end

    def test_kind_predicates
      assert_predicate @golf, :car?
      refute_predicate @golf, :motorcycle?
    end

    def test_body_type_predicates
      assert_predicate @golf, :hatchback?
      refute_predicate @golf, :suv?
      assert_predicate @tiguan, :suv?
      refute_predicate @tiguan, :hatchback?
    end

    def test_to_h
      assert_equal(
        { make: "Volkswagen", model: "Golf", slug: "volkswagen-golf",
          kind: :car, body_type: :hatchback },
        @golf.to_h
      )
    end

    def test_equality_by_slug
      assert_equal Vehicles.find("vw golf"), Vehicles.find("Volkswagen Golf")
      assert_equal Vehicles.find("vw golf").hash, Vehicles.find("Volkswagen Golf").hash
      refute_equal @golf, @tiguan
    end

    def test_dedup_in_a_set
      set = [Vehicles.find("vw golf"), Vehicles.find("Volkswagen Golf"), @tiguan].to_set

      assert_equal 2, set.size
    end

    def test_models_are_frozen
      assert_predicate @golf, :frozen?
    end

    # Hosted-only fields degrade to nil without an API key (never raise).
    def test_hosted_fields_nil_without_api_key
      assert_nil @golf.years
      assert_nil @golf.segment
      assert_nil @golf.image
      assert_nil @golf.image(year: 2020, color: :red)
    end
  end
end
