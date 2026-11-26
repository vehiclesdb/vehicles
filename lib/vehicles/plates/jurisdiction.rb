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

      def to_s = code
      def inspect = %(#<Vehicles::Plates::Jurisdiction #{code} (#{series.size} series)>)
    end
  end
end
