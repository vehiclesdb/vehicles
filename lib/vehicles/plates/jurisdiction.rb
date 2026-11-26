# frozen_string_literal: true

module Vehicles
  module Plates
    # One issuing jurisdiction — a country, or a state where plates are
    # state-issued ("us-fl"; a bare "us" will never exist). Wraps the raw
    # dataset YAML: authority, binding (vehicle vs owner), the
    # jurisdiction-wide charset law, and every series.
    class Jurisdiction
      attr_reader :code, :authority_name, :authority_url, :binding, :charset, :series

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
        # Standard first, then by class and start year; within those, series
        # still issued before ended ones, then the data file's own order (the
        # index keeps the sort stable, so ties no longer fall out arbitrarily).
        @series         = (raw["series"] || []).each_with_index.map { |entry, i| [ Series.new(entry), i ] }
          .sort_by { |s, i| [ s.klass == "standard" ? 0 : 1, s.klass, s.period["end"] || s.period["ended"] ? 1 : 0, s.period["start"] || 0, i ] }
          .map(&:first).freeze
        freeze
      end

      def to_s = code
      def inspect = %(#<Vehicles::Plates::Jurisdiction #{code} (#{series.size} series)>)
    end
  end
end
