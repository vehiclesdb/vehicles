# frozen_string_literal: true

require "test_helper"

module Vehicles
  class OptionsTest < TestCase
    def test_make_options_are_label_value_pairs
      opts = Vehicles.make_options

      assert(opts.all? { |pair| pair.size == 2 })
      assert_includes opts, %w[Audi audi]
      assert_includes opts, ["Alfa Romeo", "alfa-romeo"]
    end

    def test_make_options_follow_makes_order
      assert_equal Vehicles.makes, Vehicles.make_options.map(&:first)
    end

    def test_make_options_filtered_by_region
      assert_empty Vehicles.make_options(region: :us)
    end

    def test_model_options_are_label_value_pairs
      opts = Vehicles.model_options("audi")

      assert(opts.all? { |pair| pair.size == 2 })
      assert_includes opts, %w[A3 a3]
    end

    def test_model_options_value_is_bare_slug
      opts = Vehicles.model_options("volkswagen")
      golf = opts.find { |label, _| label == "Golf" }

      assert_equal %w[Golf golf], golf
    end

    def test_model_options_for_unknown_make_is_empty
      assert_empty Vehicles.model_options("DeLorean")
    end

    def test_model_options_filtered
      suv_opts = Vehicles.model_options("toyota", body_type: :suv)

      assert_includes suv_opts.map(&:first), "RAV4"
      refute_includes suv_opts.map(&:first), "Yaris"
    end

    def test_options_usable_with_alias
      assert_equal Vehicles.model_options("volkswagen"), Vehicles.model_options("VW")
    end
  end
end
