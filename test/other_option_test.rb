# frozen_string_literal: true

require "test_helper"

module Vehicles
  # The "Other / not in the list" escape hatch: a first-class option for make/
  # model pickers so a vehicle the dataset doesn't cover is never a dead end.
  class OtherOptionTest < TestCase
    def test_other_label_defaults_to_other_and_is_configurable
      assert_equal "Other", Vehicles.other_label

      Vehicles.configure { |c| c.other_label = "Otro" }

      assert_equal "Otro", Vehicles.other_label
    end

    def test_other_predicate_matches_label_and_canonical_slug
      Vehicles.configure { |c| c.other_label = "Otro" }

      assert Vehicles.other?("Otro")   # the configured label
      assert Vehicles.other?("otro")   # case-insensitive
      assert Vehicles.other?("other")  # the canonical slug, always recognized
      assert Vehicles.other?("OTHER")

      refute Vehicles.other?("Audi")
      refute Vehicles.other?("")
      refute Vehicles.other?(nil)
    end

    def test_makes_include_other_appends_the_label_last
      names = Vehicles.makes(include_other: true)

      assert_equal Vehicles.other_label, names.last
      assert_equal Vehicles.makes, names[0..-2] # everything else is untouched
    end

    def test_makes_without_flag_are_unchanged
      refute_includes Vehicles.makes, Vehicles.other_label
    end

    def test_models_include_other_appends_the_label
      models = Vehicles.models("Audi", include_other: true)

      assert_includes models, "A3"
      assert_equal Vehicles.other_label, models.last
    end

    def test_models_for_the_other_make_yields_just_the_hatch
      # An unknown make (e.g. the "Other" make itself) has no models, so the
      # picker still gets a single valid choice instead of an empty select.
      Vehicles.configure { |c| c.other_label = "Otro" }

      assert_equal ["Otro"], Vehicles.models("Otro", include_other: true)
    end

    def test_make_options_include_other_uses_the_stable_slug
      opts = Vehicles.make_options(include_other: true)

      assert_equal %w[Other other], opts.last
    end

    def test_model_options_include_other_uses_the_stable_slug
      opts = Vehicles.model_options("audi", include_other: true)

      assert_equal %w[Other other], opts.last
    end

    def test_appending_other_never_doubles_it
      # Idempotence guard against a future dataset that ships its own "Other".
      names = Vehicles.makes(include_other: true)

      assert_equal(1, names.count { |n| Vehicles.other?(n) })

      opts = Vehicles.make_options(include_other: true)

      assert_equal(1, opts.count { |(_label, value)| Vehicles.other?(value) })
    end
  end
end
