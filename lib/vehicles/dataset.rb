# frozen_string_literal: true

require "json"

module Vehicles
  # Loads the bundled snapshot once, builds in-memory indexes, and answers every
  # query. No HTTP, no SQLite, no ActiveRecord on the read path — the first call
  # builds the index, every call after is a hash lookup.
  #
  # Instances are memoized per data path (see .load), so the JSON is parsed once
  # per process.
  class Dataset
    # Built-in make aliases (normalized key => make slug). Common abbreviations
    # and nicknames so whatever a user types tends to land. Diacritics and case
    # are already handled by Vehicles.normalize, so "škoda"/"citroën" need no entry.
    BUILTIN_ALIASES = {
      "vw" => "volkswagen", "vdub" => "volkswagen",
      "merc" => "mercedes-benz", "mercedes" => "mercedes-benz", "benz" => "mercedes-benz",
      "mb" => "mercedes-benz",
      "chevy" => "chevrolet",
      "beemer" => "bmw", "bimmer" => "bmw",
      "alfa" => "alfa-romeo",
      "landrover" => "land-rover", "range rover" => "land-rover", "rangerover" => "land-rover",
      "vauxhall" => "opel" # GB badge-engineered Opel; map to the EU make we ship
    }.freeze

    class << self
      # Memoized per path so the bundled JSON is parsed only once per process.
      def load(path = Vehicles.data_path)
        (@instances ||= {})[path] ||= new(JSON.parse(File.read(path)))
      end

      # Drop the cache (used by the test suite between runs).
      def reset!
        @instances = {}
      end
    end

    attr_reader :version, :schema_version, :region

    def initialize(raw)
      @version        = raw["version"]
      @schema_version = raw["schema_version"]
      @region         = raw["region"]

      @makes    = (raw["makes"] || []).map { |attrs| Make.new(attrs) }
      @by_slug  = {}   # raw slug => Make
      @index    = {}   # normalized name/slug/alias => Make
      @makes.each do |make|
        @by_slug[make.slug] = make
        index(make.name, make)
        index(make.slug, make)
        make.aliases.each { |a| index(a, make) }
      end
    end

    # All makes, optionally filtered by kind/region. Unknown region => [] (honest:
    # we don't ship that pack yet), so callers never get wrong-region data.
    def makes(kind: nil, region: nil)
      return [] if region && !region_match?(region)

      list = @makes
      list = list.select { |m| m.kinds.include?(kind.to_sym) } if kind
      list
    end

    # Resolve a make from a String/Symbol/Make via aliases, slug, or name.
    def find_make(query)
      return query if query.is_a?(Make)

      q = Vehicles.normalize(query)
      return nil if q.empty?

      # 1. user-supplied aliases win
      if (canonical = Vehicles.configuration.aliases[q])
        return @by_slug[Vehicles.slugify(canonical)] || @index[Vehicles.normalize(canonical)]
      end
      # 2. built-in aliases
      if (slug = BUILTIN_ALIASES[q])
        return @by_slug[slug]
      end

      # 3. direct slug / normalized name / make alias
      @by_slug[q] || @index[q]
    end

    # Resolve a free-text "make + model" string into one Model. Tries the longest
    # leading make prefix first ("land rover defender"), then the remainder as the
    # model. Returns nil if nothing matches.
    def find_model(query)
      q = Vehicles.normalize(query)
      tokens = q.split
      return nil if tokens.empty?

      (tokens.length - 1).downto(1) do |i|
        make = find_make(tokens[0, i].join(" "))
        next unless make

        model = make.model(tokens[i..].join(" "))
        return model if model
      end
      nil
    end

    # Every model whose name (or full name) matches the query, ranked: exact name,
    # then prefix, then substring, then full-name substring. Shorter names first.
    def search(query)
      q = Vehicles.normalize(query)
      return [] if q.empty?

      scored = []
      all_models.each do |m|
        name_n = Vehicles.normalize(m.name)
        score =
          if    name_n == q              then 0
          elsif name_n.start_with?(q)    then 1
          elsif name_n.include?(q)       then 2
          elsif Vehicles.normalize(m.full_name).include?(q) then 3
          else next
          end
        scored << [score, m.name.length, m]
      end
      scored.sort_by { |score, len, _m| [score, len] }.map { |_s, _l, m| m }
    end

    # Flat list of every Model (memoized) — backs `search`.
    def all_models
      @all_models ||= @makes.flat_map(&:models)
    end

    # Does this snapshot cover the given region? (Today only :eu.)
    def region?(region)
      region_match?(region)
    end

    private

    def index(key, make)
      @index[Vehicles.normalize(key)] ||= make
    end

    def region_match?(region)
      Vehicles.normalize(region) == Vehicles.normalize(@region)
    end
  end
end
