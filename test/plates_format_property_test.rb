# frozen_string_literal: true

require "test_helper"
require "support/plate_cases"

module Vehicles
  # Property: formatting only ever inserts separators. For every series in
  # every jurisdiction, serials are generated from the series' own regex and
  # strict twin (every optional group present and absent, every branch, every
  # quantifier at its bounds) and from the display patterns of every series
  # in the same jurisdiction; each is offered to every series it matches.
  # For each match: no exception, and the formatted string with separators
  # removed is the input — nothing dropped, duplicated or reordered.
  class PlatesFormatPropertyTest < TestCase
    def test_formatting_only_inserts_separators
      checked = 0
      failures = []
      Vehicles.plates.each do |juris|
        PlateCases.for(juris).each do |serial|
          checked += check_serial(juris, serial, failures)
        end
      end

      assert_operator checked, :>=, 40_000
      assert_empty failures.first(20), "#{failures.size} of #{checked} checks failed"
    end

    # Property: the homoglyph fold is transparent. Where a jurisdiction
    # publishes `script.homoglyph_map` (ru, ua), every generated serial is
    # also offered spelled with the Cyrillic twins of its Latin letters, in
    # upper and lower case; the match must name the same series and format
    # the same string as the Latin spelling.
    def test_homoglyph_fold_is_transparent
      checked = 0
      failures = []
      Vehicles.plates.reject { |j| j.homoglyph_fold.empty? }.each do |juris|
        PlateCases.for(juris).each { |serial| checked += check_fold(juris, serial, failures) }
      end

      assert_operator checked, :>=, 1_000
      assert_empty failures.first(20), "#{failures.size} of #{checked} checks failed"
    end

    # The two defects an independent review found in the first version of
    # the repair: a non-participating optional group (nil capture) raised,
    # and overlapping captures duplicated characters.
    def test_review_regressions
      {
        ["ET123", :es] => "ET-123",
        ["ET1234VE", :es] => "ET-1234-VE",
        ["MP17Q7719", :in] => "MP 17 Q 7719",
        ["U260CD27Z", :fr] => "U 260 CD 27 Z"
      }.each do |(serial, juris), want|
        assert_equal want, Vehicles.plate(serial, jurisdiction: juris).formatted, serial
      end
    end

    private

    def check_fold(juris, serial, failures)
      unfold = juris.homoglyph_fold.invert
      latin = Vehicles.plate(serial, jurisdiction: juris.code)
      native = serial.gsub(Regexp.union(unfold.keys), unfold)
      [native, native.downcase].each do |typed|
        match = Vehicles.plate(typed, jurisdiction: juris.code)
        next if match.series == latin.series && match.formatted == latin.formatted

        failures << "#{juris.code} #{typed}: #{match.series.map(&:id)} vs #{latin.series.map(&:id)}"
      end
      2
    end

    def check_serial(juris, serial, failures)
      match = Vehicles.plate(serial, jurisdiction: juris.code)
      match.formatted
      match.series.each do |series|
        out = series.format_serial(serial)
        next if out.gsub(PlateCases::STRIP, "") == serial

        failures << "#{series.id} #{serial}: #{out.inspect}"
      end
      match.series.size
    rescue StandardError => e
      failures << "#{juris.code} #{serial}: #{e.class}: #{e.message}"
      0
    end
  end
end
