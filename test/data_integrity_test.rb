# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Guards the shape and sanity of the bundled dataset itself. If a future data
  # refresh ships something malformed, these fail loudly.
  class DataIntegrityTest < TestCase
    def setup
      @models = all_models
    end

    def test_reasonable_volume
      assert_operator Vehicles.makes.size, :>=, 40
      assert_operator @models.size, :>=, 400
    end

    def test_every_make_has_at_least_one_model
      Vehicles.makes.each do |name|
        refute_empty Vehicles.make(name).models, "#{name} has no models"
      end
    end

    def test_every_model_has_a_known_kind
      @models.each do |m|
        assert_includes Model::KINDS, m.kind, "#{m.full_name} has bad kind #{m.kind}"
      end
    end

    def test_every_model_has_a_known_body_type
      @models.each do |m|
        assert_includes Model::BODY_TYPES, m.body_type, "#{m.full_name} has bad body_type #{m.body_type}"
      end
    end

    def test_no_blank_names_or_slugs
      @models.each do |m|
        refute_empty m.name.to_s.strip, "blank model name under #{m.make}"
        assert_match(/\A[a-z0-9-]+\z/, m.slug, "bad slug #{m.slug.inspect}")
      end
    end

    def test_make_slugs_are_unique
      slugs = Vehicles.makes.map { |n| Vehicles.make(n).slug }

      assert_equal slugs, slugs.uniq
    end

    def test_model_slugs_unique_within_make
      Vehicles.makes.each do |name|
        slugs = Vehicles.make(name).models.map(&:model_slug)

        assert_equal slugs, slugs.uniq, "duplicate model slug in #{name}"
      end
    end

    def test_no_obvious_junk_nameplates
      @models.each do |m|
        refute_match(/\A\d{5,}/, m.name, "VIN-ish nameplate #{m.name}")
        refute_includes m.name, "(", "fragment nameplate #{m.name}"
      end
    end

    def test_body_type_distribution_is_plausible
      counts = @models.group_by(&:body_type).transform_values(&:size)
      # SUVs and hatchbacks dominate the modern EU market.
      assert_operator counts[:suv], :>, 100
      assert_operator counts[:hatchback], :>, 100
      assert_operator counts.fetch(:sedan, 0), :>, 30
    end

    def test_known_classifications
      # A few hand-checked anchors so a bad refresh can't silently regress them.
      assert_equal :suv, Vehicles.find("vw tiguan").body_type
      assert_equal :hatchback, Vehicles.find("vw golf").body_type
      assert_equal :sedan, Vehicles.find("audi a4").body_type
      assert_equal :coupe, Vehicles.find("porsche 911").body_type
      assert_equal :roadster, Vehicles.find("mazda mx-5").body_type
      assert_equal :mpv, Vehicles.find("renault scenic").body_type
    end

    def test_find_round_trips_for_a_sample
      sample = @models.first(50)

      sample.each do |m|
        assert_equal m, Vehicles.find(m.full_name), "round-trip failed for #{m.full_name}"
      end
    end
  end
end
