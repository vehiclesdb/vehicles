# frozen_string_literal: true

require "test_helper"

module Vehicles
  class PlatesTest < TestCase
    def test_bundled_jurisdictions_load
      assert_equal %w[de es nl us-fl], Vehicles.plates.map(&:code)
      assert_operator Vehicles.plates.sum { |j| j.series.size }, :>=, 73
    end

    def test_jurisdiction_lookup_is_forgiving
      assert_equal "nl", Vehicles.plates(:nl).code
      assert_equal "us-fl", Vehicles.plates("US_FL").code
      assert_nil Vehicles.plates(:xx)
    end

    def test_exact_match_as_issued
      match = Vehicles.plate("12-GB-BD", jurisdiction: :nl)

      assert_predicate match, :valid?
      assert_predicate match, :exact?
      assert_nil match.suggestion # nothing to suggest — typed as issued
      assert_equal "nl-sidecode6-car", match.best.id
    end

    def test_lenient_match_forgives_separators_and_suggests_the_issued_form
      # THE complaint that motivated the tier: same serial, no dashes.
      match = Vehicles.plate("12GBBD", jurisdiction: :nl)

      assert_predicate match, :valid?
      refute_predicate match, :exact?
      assert_equal "12-GB-BD", match.suggestion
    end

    def test_lenient_match_forgives_case_and_stray_spacing
      match = Vehicles.plate(" 12 gb bd ", jurisdiction: :nl)

      assert_predicate match, :valid?
      assert_equal "12-GB-BD", match.formatted
    end

    def test_strictness_survives_the_lenient_tier
      # The vowel purge (no A/E/I/O/U since sidecode 4) must reject the
      # serial from every STRICT series in BOTH tiers — leniency forgives
      # punctuation, never the alphabet. The dataset still matches it to the
      # recall-only catch-alls (export/dark-blue accept any sidecode shape),
      # which is honest — but the match must say so via strict?.
      [ "12-AB-CD", "12ABCD" ].each do |typed|
        match = Vehicles.plate(typed, jurisdiction: :nl)

        refute_predicate match, :strict?, "#{typed} must not pass any strict series"
        refute_includes match.series.map(&:id), "nl-sidecode6-car"
      end

      # A shape outside even the 14-sidecode union: invalid everywhere.
      refute_predicate Vehicles.plate("1-AB-CD", jurisdiction: :nl), :valid?
    end

    def test_garbage_and_unknown_jurisdictions_never_raise
      refute_predicate Vehicles.plate("", jurisdiction: :nl), :valid?
      refute_predicate Vehicles.plate(nil, jurisdiction: :nl), :valid?
      refute_predicate Vehicles.plate("🚗🚗🚗", jurisdiction: :nl), :valid?
      refute_predicate Vehicles.plate("12-GB-BD", jurisdiction: :atlantis), :valid?
    end

    def test_every_series_round_trips_through_the_lenient_tier
      # Structural guarantee over the WHOLE dataset: a sample generated from
      # each series' own pattern (9→digit, L→letter), stripped of separators,
      # must (a) match that series' lenient RECALL regex and (b) re-format to
      # the original patterned form. Uses `regex` (the pattern's own
      # alphabet), because pattern-generated samples may not survive strict.
      Vehicles.plates.flat_map(&:series).each do |series|
        next if series.pattern.nil? || series.regex.nil?

        sample = series.pattern.gsub("9", "1").gsub("L", "B")
        canon  = sample.gsub(Plates::SEPARATORS, "")
        lenient_recall = Regexp.new(Plates::Series.strip_separators(series.regex))

        assert_match lenient_recall, canon,
          "#{series.id}: lenient regex rejects its own pattern's sample"
        assert_equal sample, series.format_serial(canon),
          "#{series.id}: format_serial doesn't reconstruct the patterned form"
      end
    end

    def test_strip_separators_respects_character_classes
      # The "-" inside a class is a RANGE; only literal separators go.
      assert_equal '\A\d{2}[A-Z]{2}\z', Plates::Series.strip_separators('\A\d{2}-[A-Z]{2}\z')
      assert_equal '\A\d{4}[A-Z]{3}\z', Plates::Series.strip_separators('\A\d{4}\s[A-Z]{3}\z')
      assert_equal '\A\d{2}[A-Z\-]{2}\z', Plates::Series.strip_separators('\A\d{2} [A-Z\-]{2}\z')
    end

    def test_variable_length_series_reconstruct_from_the_match_not_the_pattern
      # THE Madrid bug: es-provincial's regex allows a 1-2 letter province
      # and 1-2 suffix letters, so "M1234LA" (7 chars) must come back as
      # M-1234-LA — the old fixed-slot pattern walk sliced it into
      # "M1-234L-A". Both prefix widths must reconstruct.
      assert_equal "M-1234-LA", Vehicles.plate("M1234LA", jurisdiction: :es).formatted
      assert_equal "SE-1234-AB", Vehicles.plate("SE1234AB", jurisdiction: :es).formatted
      assert_equal "M-1234-A", Vehicles.plate("M1234A", jurisdiction: :es).formatted
    end

    def test_segment_separators_shapes
      segments, separators = Plates::Series.segment_separators('\A[A-Z]{1,2}-\d{4}-[A-Z]{1,2}\z')
      assert_equal [ '[A-Z]{1,2}', '\d{4}', '[A-Z]{1,2}' ], segments
      assert_equal [ "-", "-" ], separators

      # No separators anywhere → nothing to segment, fallback territory.
      assert_equal [ nil, nil ], Plates::Series.segment_separators('\AE\d{4}[A-Z]{3}\z')
      # A separator-only class prints its first token; \s prints a space.
      _, seps = Plates::Series.segment_separators('\ACC[- ]\d{3}[- ]\d{3}\z')
      assert_equal [ "-", "-" ], seps
      _, seps = Plates::Series.segment_separators('\A\d{4}\s[A-Z]{3}\z')
      assert_equal [ " " ], seps
    end

    def test_format_serial_never_misplaces_separators_when_it_cannot_know
      # A serial the issued regex does not match and whose length does not
      # fill the pattern comes back untouched — unformatted is honest,
      # misplaced separators are not.
      series = Vehicles.plates(:es).series.find { |s| s.id == "es-provincial" }
      assert_equal "M12", series.format_serial("M12")
    end

    def test_period_label_marks_instrument_dated_starts
      # es-provincial records period_evidence: instrument-window — the 1999
      # start is RD 2822/1998's in-force date, not the format's birth. The
      # label must read "documented from", never present the window as the
      # era; open-ended periods say "today" in words.
      provincial = Vehicles.plates(:es).series.find { |s| s.id == "es-provincial" }
      assert_equal "~1999–2000", provincial.period_label
      assert_predicate provincial, :approximate_start?

      national = Vehicles.plates(:es).series.find { |s| s.id == "es-national-2000" }
      assert_match(/→ today\z/, national.period_label)

      # An exact-evidence series keeps the plain label.
      sidecode = Vehicles.plates(:nl).series.find { |s| s.id == "nl-sidecode6-car" }
      refute_predicate sidecode, :approximate_start?
      refute_match(/~/, sidecode.period_label)
    end
  end
end
