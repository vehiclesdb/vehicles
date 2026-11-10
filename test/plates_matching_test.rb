# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Strictness is the dataset's `matching:` key (PRD-PLATES §2.7), and the
  # Spanish cases are the shapes CarHey's production fleet actually holds
  # (aggregate shape masks from the 2026-11-10 dry run, filled with made-up
  # serials; no real plate is in this file).
  class PlatesMatchingTest < TestCase
    def test_strict_is_read_from_matching_never_inferred_from_regex_strict
      Vehicles.plates.flat_map(&:series).each do |series|
        assert_equal series.matching != "recall-only", series.strict?, series.id
      end
    end

    def test_strict_series_without_a_strict_twin_are_strict
      # pt-national-2020 has no regex_strict: its regex IS the grammar.
      # Until 0.9.2 it answered strict? == false (2 of CarHey's 3 PT cars).
      match = Vehicles.plate("AA-12-BB", jurisdiction: :pt)

      assert_predicate match, :strict?
      assert_equal "pt-national-2020", match.best.id

      assert_predicate Vehicles.plate("CD-123-45", jurisdiction: :es), :strict?
    end

    def test_recall_only_series_stay_shape_hits
      # es-provincial-numeric (1900-1971) is a deliberately wide union.
      %w[M-123456 ABC1234].each do |typed|
        match = Vehicles.plate(typed, jurisdiction: :es)

        assert_predicate match, :valid?, typed
        refute_predicate match, :strict?, typed
        assert_equal "es-provincial-numeric", match.best.id
      end
    end

    SPANISH_STRICT = {
      "1234BCD" => "es-national-2000", "1234 bcd" => "es-national-2000", "0000BBB" => "es-national-2000",
      "M-1234-AB" => "es-provincial", "PM1234A" => "es-provincial", "GE1234AE" => "es-provincial",
      "SS1234Z" => "es-provincial", "LO1234BC" => "es-provincial", "CS1234AB" => "es-provincial",
      "GC1234AA" => "es-provincial", "TF1234B" => "es-provincial", "BI1234CD" => "es-provincial",
      "H1234BCD" => "es-historic-1999", "P1234BCD" => "es-temporary-private-1999",
      "S1234BCD" => "es-temporary-company-unregistered-1999", "V1234BCD" => "es-temporary-company-registered-1999",
      "V1234BC" => "es-provincial", "T1234BCD" => "es-tourist-1999",
      "C1234BCD" => "es-moped-1999", "R1234BCD" => "es-trailer-1999", "E1234BCD" => "es-special-vehicles-1999"
    }.freeze

    def test_spanish_series_carhey_holds
      SPANISH_STRICT.each do |typed, series|
        match = Vehicles.plate(typed, jurisdiction: :es)

        assert_predicate match, :strict?, typed
        assert_equal series, match.best.id, typed
      end
    end

    # Every non-plate shape in CarHey's ES column: none is a Spanish plate.
    SPANISH_NOT_PLATES = %w[
      1234ABC 1234BCQ 1234 1234BC 123BCD 12345BCD 1234B 1234BCDF AB12CD BCDF123 ABCDEF123 ABCDEFGHIJ
      XX1234AB QQ1234B
    ].freeze

    def test_shapes_spain_does_not_issue
      SPANISH_NOT_PLATES.each do |typed|
        refute_predicate Vehicles.plate(typed, jurisdiction: :es), :strict?, typed
      end
    end

    def test_near_misses_name_the_series_whose_alphabet_was_broken
      # The classic: the 2000 shape with vowels (CarHey's own placeholder
      # read "1234ABC" for months).
      match = Vehicles.plate("1234 ABC", jurisdiction: :es)

      refute_predicate match, :valid?
      assert_equal ["es-national-2000"], match.near_misses.map(&:id)
      assert_equal %w[A E I O U Ñ Q], match.jurisdiction.charset["excluded_letters"]

      assert_equal ["es-national-2000"], Vehicles.plate("1234BCQ", jurisdiction: :es).near_misses.map(&:id)
      assert_empty Vehicles.plate("1234BCD", jurisdiction: :es).near_misses # a hit is never a near miss
      assert_empty Vehicles.plate("1234", jurisdiction: :es).near_misses # no shape at all
      assert_empty Vehicles.plate("1234ABC", jurisdiction: :atlantis).near_misses
    end

    def test_template_series_prefers_the_strict_hit
      # "CD123456" fits the diplomatic series (strict) AND the 1900-1971
      # numeric catch-all (recall-only, class standard). It is drawn as the
      # diplomatic plate, never as a provincial one.
      found = Vehicles.plate("CD123456", jurisdiction: :es)

      assert_equal "es-diplomatic-cd-1999", Plates.template_series(found).id

      assert_equal "es-national-2000", Plates.template_series(Vehicles.plate("1234BCD", jurisdiction: :es)).id
      assert_equal "es-provincial-numeric", Plates.template_series(Vehicles.plate("M123456", jurisdiction: :es)).id
    end

    def test_near_misses_follow_the_broken_series_not_a_fixed_alphabet
      # An unknown province code is a near miss of es-provincial, and carries
      # no excluded letter: a form must not blame vowels for it.
      match = Vehicles.plate("XX1234BC", jurisdiction: :es)

      assert_equal ["es-provincial"], match.near_misses.map(&:id)
      assert_nil match.near_misses.first.letters # province codes, not a letter set, are what failed

      # The national series enumerates its letters, so a form can tell the
      # alphabet was the problem.
      national = Vehicles.plate("1234ABC", jurisdiction: :es).near_misses.first

      assert_equal %w[B C D F G H J K L M N P R S T V W X Y Z], national.letters
    end

    def test_formatted_never_invents_an_ambiguous_split
      # Variable-width groups: "CD12345" is CD-123-45 or CD-1234-5; the bare
      # serial cannot say which, so it comes back as stored.
      assert_equal "CD12345", Vehicles.plate("CD12345", jurisdiction: :es).formatted
      # Fills the representative CD-999-999, and is still ambiguous.
      assert_equal "CD123456", Vehicles.plate("CD-12-3456", jurisdiction: :es).formatted
      assert_equal "M-1234-AB", Vehicles.plate("M1234AB", jurisdiction: :es).formatted
      assert_equal "BI-1234-C", Vehicles.plate("BI1234C", jurisdiction: :es).formatted
      assert_equal "M-123456", Vehicles.plate("M123456", jurisdiction: :es).formatted
    end
  end
end
