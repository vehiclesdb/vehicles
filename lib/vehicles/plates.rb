# frozen_string_literal: true

require "yaml"

module Vehicles
  # License-plate & registration-mark knowledge (the VehiclesDB PRD-PLATES
  # dataset, bundled offline like everything else in this gem). Ask it two
  # kinds of question:
  #
  #   Vehicles.plates                 # => every Jurisdiction
  #   Vehicles.plates(:nl)            # => one Jurisdiction (series, charset, authority)
  #   Vehicles.plate("12-GB-BD", jurisdiction: :nl)   # => Plates::Match
  #
  # Matching is TWO-TIER, because humans type plates every way at once:
  #
  #   exact   — the input, upcased, matches a series' STRICT regex as-typed
  #             (separators included): formatted exactly as issued.
  #   lenient — the input with separators stripped ("1234XYZ", "1234 xyz",
  #             "1234-XYZ" all collapse to "1234XYZ") matches the same strict
  #             alphabet with the separators removed. Still the authority's
  #             real issuing alphabet — only the punctuation is forgiven.
  #
  # A lenient-only match carries `suggestion`: the serial re-formatted the
  # way it appears on the physical plate ("did you mean 1234 XYZ").
  # Same posture as every lookup in this gem: garbage in => empty result,
  # never an exception.
  module Plates
    DATA_DIR = File.expand_path("../../data/plates", __dir__)

    # What people type between plate groups: space(s), hyphen/en/em dash,
    # middot, period. Stripped for the lenient tier (and from the strict
    # regexes to derive their lenient twins).
    SEPARATORS = /[\s\-–—·.]+/

    module_function

    def jurisdictions
      @jurisdictions ||= Dir.glob(File.join(DATA_DIR, "*.yml")).sort.map do |path|
        Jurisdiction.load(path)
      end
    end

    def jurisdiction(code)
      jurisdictions.find { |j| j.code == code.to_s.downcase.tr("_", "-") }
    end

    def classes
      @classes ||= YAML.safe_load_file(File.join(DATA_DIR, "_meta", "classes.yml")) || {}
    end

    # The matcher behind Vehicles.plate. Unknown jurisdiction => empty Match.
    def match(input, jurisdiction:)
      juris = jurisdiction(jurisdiction)
      typed = input.to_s.upcase.strip
      canon = typed.gsub(SEPARATORS, "")
      return Match.new(input: input.to_s, jurisdiction: juris, canon: canon, hits: []) if juris.nil? || canon.empty?

      hits = juris.series.filter_map do |series|
        next nil unless series.validation_regexp

        exact = series.validation_regexp.match?(typed)
        lenient = exact || series.lenient_regexp&.match?(canon)
        Match::Hit.new(series: series, exact: exact) if lenient
      end

      Match.new(input: input.to_s, jurisdiction: juris, canon: canon, hits: hits)
    end

    # The answer to "is this a plate, and which series issues it?".
    class Match
      Hit = Struct.new(:series, :exact, keyword_init: true) do
        def exact? = exact
      end

      attr_reader :input, :jurisdiction, :canon, :hits

      def initialize(input:, jurisdiction:, canon:, hits:)
        @input = input
        @jurisdiction = jurisdiction
        @canon = canon
        # Exact hits outrank lenient ones, strict-validated series outrank
        # recall-only catch-alls; series order (standard first) breaks ties.
        @hits = hits.sort_by { |h| [ h.exact? ? 0 : 1, h.series.strict? ? 0 : 1 ] }.freeze
        freeze
      end

      def valid? = hits.any?
      def exact? = hits.any?(&:exact?)

      # True when at least one hit is a strict-validated series — the strong
      # signal ("the authority issues this alphabet"), vs a catch-all shape
      # union like an export plate. Prefer this for user-input validation.
      def strict? = hits.any? { |h| h.series.strict? }

      def series = hits.map(&:series)
      def best = hits.first&.series

      # The serial formatted the way the best-matching series prints it on
      # the physical plate — "1234XYZ" typed, "1234 XYZ" issued.
      def formatted
        best&.format_serial(canon)
      end

      # Only when the user's punctuation was off: the "did you mean" string.
      def suggestion
        formatted if valid? && !exact?
      end
    end
  end
end
