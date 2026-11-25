# frozen_string_literal: true

require "test_helper"

module Vehicles
  class PlatesTest < TestCase
    def test_bundled_jurisdictions_load
      codes = Vehicles.plates.map(&:code)
      assert_operator codes.size, :>=, 67
      # The four pilots, the L1 EU wave, and the US federation all present.
      %w[de es nl us-fl gb ch at fr it be se fi us-ca us-ny us-tx us-pr].each do |code|
        assert_includes codes, code
      end
      assert_operator Vehicles.plates.sum { |j| j.series.size }, :>=, 600
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

        # Escape-aware: "\L" is a LITERAL L (ca-nb-truck) and must survive
        # untouched; bare placeholders substitute 9→1, L→B.
        sample = series.pattern.gsub(/\\.|[9L]/) { |m| { "9" => "1", "L" => "B" }[m] || m[1] }
        canon  = sample.gsub(Plates::SEPARATORS, "")
        lenient_recall = Regexp.new(Plates::Series.strip_separators(series.regex))

        assert_match lenient_recall, canon,
          "#{series.id}: lenient regex rejects its own pattern's sample"
        # A series whose regex can split the sample more than one way
        # (variable-width groups: ES diplomatic, personalised plates) returns
        # it as stored rather than invent a split.
        expected = series.ambiguous_split?(canon) ? canon : sample
        assert_equal expected, series.format_serial(canon),
          "#{series.id}: format_serial doesn't reconstruct the patterned form"
      end
    end

    def test_strip_separators_respects_character_classes
      # The "-" inside a class is a RANGE; only literal separators go.
      assert_equal '\A\d{2}[A-Z]{2}\z', Plates::Series.strip_separators('\A\d{2}-[A-Z]{2}\z')
      assert_equal '\A\d{4}[A-Z]{3}\z', Plates::Series.strip_separators('\A\d{4}\s[A-Z]{3}\z')
      assert_equal '\A\d{2}[A-Z\-]{2}\z', Plates::Series.strip_separators('\A\d{2} [A-Z\-]{2}\z')
    end

    def test_strip_separators_collapses_redundant_character_class_repeats
      # Removing the separator from these real dataset shapes otherwise leaves
      # nested repeats such as `[A-Z0-9]+(?:[A-Z0-9]+)*`. Ruby (3.1+) warns while
      # compiling them. Both languages are exactly one-or-more characters from
      # the same class, so return that canonical equivalent instead.
      repeated = Plates::Series.strip_separators('\A[A-Z0-9]+(?:-[A-Z0-9]+)*\z')
      optional = Plates::Series.strip_separators('\A[A-Z0-9]+(?: [A-Z0-9]+)?\z')

      assert_equal '\A[A-Z0-9]+\z', repeated
      assert_equal '\A[A-Z0-9]+\z', optional
    end

    def test_every_lenient_regex_compiles_without_nested_repeat_warnings
      # The same source production feeds into compile: regex_strict when a
      # series has one (427 of them do), regex otherwise. Auditing only
      # `regex` would leave the strict variants unguarded.
      _, warnings = capture_io do
        Vehicles.plates.flat_map(&:series).filter_map { |series| series.regex_strict || series.regex }.each do |source|
          Regexp.new(Plates::Series.strip_separators(source))
        end
      end

      warning_lines = warnings.lines.grep(/nested repeat operator/)

      assert_empty warning_lines, "separator stripping generated a nested-repeat regexp"
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
      # es-provincial is the redate-pass success story: once dated
      # 1999–2000 off an instrument window, now 1971–2000 pinned to
      # Decreto 2046/1971 at both ends — so NO approximation mark. The
      # un-pinned cases keep the "~": us-fl-standard's 2003 rests on an
      # uncited secondary. Open-ended periods say "today" in words.
      provincial = Vehicles.plates(:es).series.find { |s| s.id == "es-provincial" }
      assert_equal "1971–2000", provincial.period_label
      refute_predicate provincial, :approximate_start?

      national = Vehicles.plates(:es).series.find { |s| s.id == "es-national-2000" }
      assert_match(/→ today\z/, national.period_label)

      fl_standard = Vehicles.plates("us-fl").series.find { |s| s.id == "us-fl-standard" }
      assert_predicate fl_standard, :approximate_start?
      assert_match(/\A~/, fl_standard.period_label)

      # An exact-evidence series keeps the plain label.
      sidecode = Vehicles.plates(:nl).series.find { |s| s.id == "nl-sidecode6-car" }
      refute_predicate sidecode, :approximate_start?
      refute_match(/~/, sidecode.period_label)
    end
    def test_decode_tables_load_by_name
      table = Plates.decode_table("at-districts")
      assert_operator table["codes"].length, :>=, 98
      assert_equal "Wien", table["codes"].find { |r| r["code"] == "W" }["land"]
      assert_nil Plates.decode_table("no-such-table")
    end
    def test_gb_year_letters_table
      table = Plates.decode_table("gb-year-letters")
      rows = table["letters"]
      assert_equal(21, rows.count { |r| r["system"] == "suffix" })
      assert_equal(21, rows.count { |r| r["system"] == "prefix" })
      k_prefix = rows.find { |r| r["system"] == "prefix" && r["letter"] == "K" }
      assert_equal %w[1992-08 1993-07], k_prefix.values_at("from", "to")
      assert_empty rows.map { |r| r["letter"] }.uniq & %w[I O Q U Z]
      ids = table["sources"].map { |s| s["id"] }
      assert_empty rows.flat_map { |r| r["sources"] } - ids
    end

    # Indonesia: Perpol 7/2021 gives the grammar in words — region code of
    # 1-2 letters, 1-4 digits, 0-3 series letters — and four registration
    # codes (CD, CC, CH, RI) that replace the region code. Serials below are
    # synthetic except the regulation's own examples (CD 12 5, RI 1).
    def id_series_ids(serial)
      Vehicles.plate(serial, jurisdiction: :id).series.map(&:id)
    end

    def test_indonesia_loads
      ids = Vehicles.plates(:id).series.map(&:id)
      assert_equal 18, ids.size
      %w[id-private-white-2022 id-private-black-1993 id-diplomatic-cd-2006
         id-state-ri-2006 id-trial-tckb-2006 id-crossborder-lbn-2021].each do |sid|
        assert_includes ids, sid
      end
    end

    def test_indonesia_ordinary_plate_and_region_list
      ordinary = Vehicles.plate("B 1234 ABC", jurisdiction: :id)
      assert_predicate ordinary, :exact?
      assert_predicate ordinary, :strict?
      assert_includes ordinary.series.map(&:id), "id-private-white-2022"
      assert_equal "B 1234 ABC", Vehicles.plate("b1234abc", jurisdiction: :id).formatted
      # The white plate's strict twin carries the closed region-code list
      # (Lampiran A + the 2024 Papua codes).
      refute_includes id_series_ids("XQ 1234 AB"), "id-private-white-2022"
      assert_includes id_series_ids("PG 1234 AB"), "id-private-white-2022"
    end

    def test_indonesia_registration_codes_and_class_letters
      assert_includes id_series_ids("CD 12 5"), "id-diplomatic-cd-2006"
      # 46 is one of the four codes the annex's country table skips.
      refute_includes id_series_ids("CD 46 5"), "id-diplomatic-cd-2006"
      assert_includes id_series_ids("RI 1"), "id-state-ri-2006"
      assert_includes id_series_ids("B 1234 XY"), "id-trial-tckb-2006"
      refute_includes id_series_ids("B 1234 XZ"), "id-trial-tckb-2006"
    end

    def test_indonesia_press_and_wikipedia_series_are_recall_only
      { "B 1234 ZZH" => "id-special-zz-2023", "RI 5-1" => "id-state-ri-subnumbered-2024" }.each do |serial, sid|
        series = Vehicles.plate(serial, jurisdiction: :id).series.find { |s| s.id == sid }
        refute_nil series, serial
        refute_predicate series, :strict?
      end
    end

    def test_indonesia_region_codes_table
      regions = Plates.decode_table("id-region-codes")
      assert_equal 57, regions["codes"].size
      yogya = regions["codes"].find { |r| r["code"] == "AB" }
      assert_equal "DI Yogyakarta", yogya["province"]
      assert_includes yogya["areas_printed"], "Kab. Sleman"
      assert_equal(%w[PY PS PT PG], regions["post_annex_codes"].map { |r| r["code"] })
      # Secondary tier (Wikipedia, PRD-PLATES §4): per-regency suffix letters.
      jakarta = regions["sub_area_suffixes"]["by_code"]["B"]["four_wheel_plus"]
      assert_equal(%w[D** S**], jakarta.find { |r| r["area"] == "Jakarta Selatan" }["letters"])
    end

    def test_indonesia_diplomatic_and_service_tables
      diplomatic = Plates.decode_table("id-diplomatic-codes")
      assert_equal 130, diplomatic["codes"].size
      assert_equal "US", diplomatic["codes"][12]["iso"]
      assert_equal "NO", diplomatic["codes"][19]["iso"] # quoted: a bare NO loads as false
      assert_equal "RFS", Plates.decode_table("id-service-codes")["rf_letters"]["rows"].first["letters"]
    end

    # Regression net for format_serial. The fixture holds, for every series
    # in every bundled jurisdiction, four serials generated from the series'
    # own display pattern (seeded by the series id) and what format_serial
    # printed for them BEFORE the variable-length fix below. Every row must
    # still print the same. Rows whose series no longer exists are skipped
    # (ids are append-only, so that means a renamed fixture, not a removal).
    # To regenerate after a deliberate change, rebuild the TSV from the same
    # generator and review the diff row by row.
    FORMAT_SNAPSHOT = File.expand_path("fixtures/plates_format_snapshot.tsv", __dir__)

    def test_every_series_formats_its_own_samples_unchanged
      by_id = Vehicles.plates.flat_map(&:series).to_h { |s| [ s.id, s ] }
      rows = File.readlines(FORMAT_SNAPSHOT, chomp: true).reject { |l| l.start_with?("#") }
      assert_operator rows.size, :>=, 5000
      changed = rows.filter_map do |line|
        id, serial, expected = line.split("\t", 3)
        series = by_id[id] or next
        got = series.format_serial(serial)
        "#{id} #{serial}: #{expected.inspect} -> #{got.inspect}" unless got == expected
      end
      assert_empty changed
    end

    # The two shapes the fix is for. "BL1234AB" has as many characters as the
    # display pattern "L 9999 LLL" has slots, and the old walk sliced it into
    # "B L123 4AB"; an empty trailing letter group printed a trailing
    # separator ("DK 1 ").
    def test_format_serial_variable_length_groups_and_empty_groups
      white = Vehicles.plates(:id).series.find { |s| s.id == "id-private-white-2022" }
      assert_equal "BL 1234 AB", white.format_serial("BL1234AB")
      assert_equal "DK 1", white.format_serial("DK1")
      assert_equal "B 1234 ABC", white.format_serial("B1234ABC")
      assert_equal "KB 2089 CZ", white.format_serial("KB2089CZ")
      assert_equal "BL 1234 AB", Vehicles.plate("bl1234ab", jurisdiction: :id).formatted
      assert_equal "DK 1", Vehicles.plate("DK1", jurisdiction: :id).formatted
    end

    # Ties after [exact, strict] are broken by the jurisdiction's own series
    # order (standard first, then class, then period start), explicitly, so
    # `best` is the same on every run and every Ruby.
    def test_match_ties_follow_jurisdiction_series_order
      order = Vehicles.plates(:id).series.map(&:id)
      match = Vehicles.plate("B 1234 ABC", jurisdiction: :id)
      tied = match.hits.select { |h| h.exact? && h.series.strict? }.map { |h| h.series.id }
      assert_operator tied.size, :>=, 5
      assert_equal tied.sort_by { |id| order.index(id) }, tied
      assert_equal tied.first, match.best.id
      assert_equal match.series.map(&:id), id_series_ids("B 1234 ABC")
    end
  end
end
