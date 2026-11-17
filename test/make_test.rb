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
      assert_nil Vehicles.make("Zzyzx Motors")
      # "Tesler" is one edit from Tesla: typo-tolerant by default since 0.7.8,
      # unknown under exact-only resolution.
      assert_nil Vehicles.make("Tesler", fuzzy: false)
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

    def test_model_lookup_is_exact_not_prefix
      # Partial input must NOT resolve — the vehicle_model validator relies on this.
      assert_nil @audi.model("a")
      assert_nil @audi.model("q")
      assert_equal "A3", @audi.model("a3").name
    end

    def test_models_list_is_frozen_so_callers_cannot_corrupt_it
      assert_predicate @audi.models, :frozen?
      assert_raises(FrozenError) { @audi.models << "boom" }
      # and the global state is intact
      assert_equal @audi.models, Vehicles.make("Audi").models
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

    # Country of origin (dataset 2026.11.10+): where the marque was founded.
    def test_country_of_origin
      assert_equal "de", Vehicles.make("BMW").country
      assert_equal "manufacturer", Vehicles.make("BMW").country_tier
      assert_empty Vehicles.make("BMW").country_disputed
      assert_equal %w[de], Vehicles.make("BMW").origin_countries
      # Founded in Oxford; the owner's country is never the origin.
      assert_equal "gb", Vehicles.make("MG").country
    end

    def test_disputed_origin_has_candidates_and_no_country
      leyland_daf = Vehicles.make("leyland-daf")

      assert_nil leyland_daf.country
      assert_nil leyland_daf.country_tier
      assert_equal %w[gb nl], leyland_daf.country_disputed
      assert_equal %w[gb nl], leyland_daf.origin_countries
      # Smart (and its first name, MCC) was founded as a Swiss-German venture.
      assert_equal %w[ch de], Vehicles.make("smart").country_disputed
    end

    def test_origin_is_well_formed_wherever_published
      makes = Vehicles.makes.map { |name| Vehicles.make(name, fuzzy: false) }
      with_origin = makes.reject { |m| m.origin_countries.empty? }

      assert_operator with_origin.size, :>=, 100
      with_origin.each { |m| assert_well_formed_origin(m) }
    end

    def assert_well_formed_origin(make)
      assert_empty make.origin_countries.grep_v(/\A[a-z]{2}\z/), make.slug
      assert_equal !make.country.nil?, !make.country_tier.nil?, make.slug

      assert_empty make.country_disputed, make.slug if make.country

      assert_includes [nil, "manufacturer", "regulator", "archive"], make.country_tier, make.slug
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
