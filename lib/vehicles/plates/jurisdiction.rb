# frozen_string_literal: true

module Vehicles
  module Plates
    # One issuing jurisdiction — a country, or a state where plates are
    # state-issued ("us-fl"; a bare "us" will never exist). Wraps the raw
    # dataset YAML: authority, binding (vehicle vs owner), the
    # jurisdiction-wide charset law, and every series.
    class Jurisdiction
      attr_reader :code, :authority_name, :authority_url, :binding, :charset, :series, :homoglyph_fold

      def self.load(path)
        raw = YAML.safe_load_file(path, aliases: true)
        new(code: File.basename(path, ".yml"), raw: raw)
      end

      def initialize(code:, raw:)
        @code           = code
        @authority_name = raw.dig("authority", "name")
        @authority_url  = raw.dig("authority", "url")
        @binding        = raw["binding"]
        @charset        = (raw["charset_defaults"] || {}).freeze
        @homoglyph_fold = self.class.homoglyph_fold(raw.dig("script", "homoglyph_map"))
        @fold_regexp    = Regexp.union(@homoglyph_fold.keys) unless @homoglyph_fold.empty?
        @series         = (raw["series"] || []).each_with_index
          .map { |entry, i| [ Series.new(entry), i ] }
          .sort_by { |s, i| self.class.series_rank(s, i) }
          .map(&:first).freeze
        freeze
      end

      # Standard class first, then by class; within a class a series still
      # issued before an ended one, then earliest start, then the data file's
      # own order. The file index makes the order total: sort_by is not
      # stable, so ties used to fall out in an order nobody chose.
      def self.series_rank(series, index)
        ended = series.period["end"] || series.period["ended"]
        [ series.klass == "standard" ? 0 : 1, series.klass, ended ? 1 : 0, series.period["start"] || 0, index ]
      end

      # Input as the dataset spells it. Where a jurisdiction prints letters of
      # another script that look like Latin ones (the twelve Cyrillic plate
      # letters of ru and ua), the dataset writes them as their Latin twins and
      # publishes the map in `script.homoglyph_map` ("А U+0410" => "A"). Folding
      # by that map lets "А 123 ВС 77" typed in Cyrillic match the regexes;
      # anything outside the map is left alone. Expects upper-cased input.
      def fold(text)
        return text unless @fold_regexp

        text.gsub(@fold_regexp, @homoglyph_fold)
      end

      # `script.homoglyph_map` keys are "<char> U+XXXX"; the codepoint must name
      # the character, and each side must be one character, or the entry is
      # ignored (a malformed row must never fold the wrong letter).
      def self.homoglyph_fold(map)
        return {}.freeze unless map.is_a?(Hash)

        map.each_with_object({}) do |(key, latin), out|
          char, cp = key.to_s.split(" ", 2)
          next unless char&.length == 1 && latin.is_a?(String) && latin.length == 1
          next unless cp == format("U+%04X", char.ord)

          out[char] = latin
        end.freeze
      end

      def to_s = code
      def inspect = %(#<Vehicles::Plates::Jurisdiction #{code} (#{series.size} series)>)
    end
  end
end
