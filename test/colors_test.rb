# frozen_string_literal: true

require "test_helper"

module Vehicles
  class ColorsTest < TestCase
    def test_colors_are_color_objects
      assert(Vehicles.colors.all?(Vehicles::Color))
      assert_operator Vehicles.colors.size, :>=, 10
    end

    def test_palette_covers_the_essentials
      slugs = Vehicles.colors.map(&:slug)

      %w[white black grey silver blue red green other].each { |s| assert_includes slugs, s }
    end

    def test_color_attributes
      white = Vehicles.color("white")

      assert_equal "white", white.slug
      assert_equal "White", white.name
      assert_match(/\A#[0-9A-F]{6}\z/i, white.hex)
      assert_equal({ slug: "white", name: "White", hex: white.hex }, white.to_h)
    end

    def test_color_lookup_is_forgiving
      assert_equal Vehicles.color("white"), Vehicles.color("White")
      assert_equal Vehicles.color("white"), Vehicles.color("WHITE")
      assert_equal "grey", Vehicles.color("gray").slug    # synonym
      assert_equal "blue", Vehicles.color("navy").slug    # synonym
      assert_equal "beige", Vehicles.color("tan").slug    # synonym
    end

    def test_color_returns_nil_for_unknown
      assert_nil Vehicles.color("chartreuse")
      assert_nil Vehicles.color("")
      assert_nil Vehicles.color(nil)
    end

    def test_color_options_are_label_value_pairs
      opts = Vehicles.color_options

      assert(opts.all? { |label, value| label.is_a?(String) && value.is_a?(String) })
      assert_includes opts, %w[White white]
    end

    def test_colors_are_frozen
      assert_predicate Vehicles.color("red"), :frozen?
    end
  end
end
