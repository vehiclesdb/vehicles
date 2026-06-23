# frozen_string_literal: true

require "test_helper"

module Vehicles
  class ValidatorsTest < TestCase
    # A plain tableless ActiveModel object, the way a host app's model would use
    # the drop-in validators.
    class Car
      include ActiveModel::Model

      attr_accessor :make, :model

      validates :make, vehicle_make: true
      validates :model, vehicle_model: { make: :make }
    end

    class CarRequired
      include ActiveModel::Model

      attr_accessor :make

      validates :make, presence: true, vehicle_make: true
    end

    def setup
      skip "ActiveModel not available" unless defined?(ActiveModel::EachValidator)
    end

    def test_valid_make_and_model
      assert_predicate Car.new(make: "Volkswagen", model: "Golf"), :valid?
    end

    def test_valid_with_alias_and_case
      assert_predicate Car.new(make: "VW", model: "golf"), :valid?
    end

    def test_invalid_make
      car = Car.new(make: "Tesler", model: "Model 3")

      refute_predicate car, :valid?
      assert_includes car.errors[:make], "is not a recognized vehicle make"
    end

    def test_invalid_model_for_valid_make
      car = Car.new(make: "Volkswagen", model: "Mustang")

      refute_predicate car, :valid?
      assert_includes car.errors[:model], "is not a recognized Volkswagen model"
    end

    def test_blank_values_pass_make_and_model_validators
      # blank is allowed by these validators (pair with presence: true to forbid)
      assert_predicate Car.new(make: "", model: ""), :valid?
      assert_predicate Car.new(make: nil, model: nil), :valid?
    end

    def test_presence_composes
      refute_predicate CarRequired.new(make: nil), :valid?
      assert_predicate CarRequired.new(make: "Audi"), :valid?
    end

    def test_model_validator_defers_when_make_unknown
      # an unknown make can't disprove the model; the make validator flags it
      car = Car.new(make: "Tesler", model: "whatever")
      car.valid?

      assert_empty car.errors[:model]
      refute_empty car.errors[:make]
    end

    def test_custom_message
      klass = Class.new do
        include ActiveModel::Model

        attr_accessor :brand

        validates :brand, vehicle_make: { message: "pick a real car brand" }
        def self.name = "CustomCar"
      end
      car = klass.new(brand: "Nope")

      refute_predicate car, :valid?
      assert_includes car.errors[:brand], "pick a real car brand"
    end
  end
end
