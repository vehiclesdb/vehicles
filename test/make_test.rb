# frozen_string_literal: true

require "test_helper"

module Vehicles
  class MakeTest < TestCase
    def setup
      @audi = Vehicles.make("Audi")
    end

    def test_make_returns_a_make
      assert_instance_of Vehicles::Make, @audi
      assert_equal "Audi", @audi.name
      assert_equal "audi", @audi.slug
    end

    def test_make_is_forgiving
      assert_equal @audi, Vehicles.make("audi")
      assert_equal @audi, Vehicles.make("AUDI")
      assert_equal Vehicles.make("Volkswagen"), Vehicles.make("VW")
    end

    def test_make_returns_nil_for_unknown
      assert_nil Vehicles.make("Tesler")
      assert_nil Vehicles.make("")
      assert_nil Vehicles.make(nil)
    end

    def test_make_passes_through_make_object
      assert_same @audi, Vehicles.make(@audi)
    end

    def test_kinds
      assert_equal [:car], @audi.kinds
    end

    def test_models_are_model_objects
      assert(@audi.models.all?(Vehicles::Model))
      assert_includes @audi.model_names, "A3"
    end

    def test_models_filtered
      assert(@audi.models(body_type: :suv).all?(&:suv?))
      assert_includes @audi.model_names(body_type: :suv), "Q3"
      refute_includes @audi.model_names(body_type: :suv), "A3"
    end

    def test_model_lookup_within_make
      a3 = @audi.model("a3")

      assert_instance_of Vehicles::Model, a3
      assert_equal "A3", a3.name
      assert_equal @audi.model("A3"), @audi.model("a3")
    end

    def test_model_lookup_returns_nil_for_unknown
      assert_nil @audi.model("Mustang")
      assert_nil @audi.model("")
    end

    def test_model_options
      opts = @audi.model_options

      assert(opts.all? { |label, value| label.is_a?(String) && value.is_a?(String) })
      assert_includes opts, %w[A3 a3]
    end

    def test_to_h
      h = @audi.to_h

      assert_equal "Audi", h[:name]
      assert_equal "audi", h[:slug]
      assert_includes h[:models], "A3"
    end

    def test_to_s_is_name
      assert_equal "Audi", @audi.to_s
    end

    def test_equality_and_hash
      assert_equal Vehicles.make("audi"), Vehicles.make("AUDI")
      assert_equal Vehicles.make("audi").hash, Vehicles.make("AUDI").hash
      refute_equal Vehicles.make("audi"), Vehicles.make("bmw")
    end
  end
end
