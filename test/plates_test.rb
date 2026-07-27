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
  end
end
