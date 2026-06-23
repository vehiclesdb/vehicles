# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Covers the normalize/slugify helpers and dataset memoization — the small,
  # load-bearing primitives every lookup depends on.
  class HelpersTest < TestCase
    def test_normalize_folds_case_and_whitespace
      assert_equal "mercedes benz", Vehicles.normalize("  Mercedes-Benz  ")
      assert_equal "vw golf", Vehicles.normalize("VW   Golf")
    end

    def test_normalize_strips_diacritics
      assert_equal "skoda", Vehicles.normalize("Škoda")
      assert_equal "citroen", Vehicles.normalize("Citroën")
      assert_equal "megane", Vehicles.normalize("Mégane")
    end

    def test_normalize_handles_nil_and_symbols
      assert_equal "", Vehicles.normalize(nil)
      assert_equal "eu", Vehicles.normalize(:eu)
    end

    def test_normalize_never_raises_on_invalid_encoding
      # The lookup API promises "garbage in => empty/nil out", never an exception.
      assert_equal "", Vehicles.normalize("\xFF\xFE".b)
      assert_kind_of String, Vehicles.slugify("\xC3\x28".b)
    end

    def test_lookups_survive_invalid_encoding
      assert_nil Vehicles.make("\xFF\xFE".b)
      assert_empty Vehicles.models("\xFF".b)
      assert_nil Vehicles.find("\xFF golf".b)
      assert_empty Vehicles.search("\xFF".b)
    end

    def test_slugify
      assert_equal "alfa-romeo", Vehicles.slugify("Alfa Romeo")
      assert_equal "skoda", Vehicles.slugify("Škoda")
      assert_equal "citroen", Vehicles.slugify("Citroën")
      assert_equal "c-hr", Vehicles.slugify("C-HR")
      assert_equal "mercedes-benz", Vehicles.slugify("Mercedes-Benz")
    end

    def test_dataset_is_memoized
      assert_same Vehicles.dataset, Vehicles.dataset
    end

    def test_region_query
      assert Vehicles.dataset.region?(:eu)
      assert Vehicles.dataset.region?("EU")
      refute Vehicles.dataset.region?(:us)
    end
  end
end
