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
      "landrover" => "land-rover", "range rover" => "land-rover", "rangerover" => "land-rover"
      # NOTE: no "vauxhall" alias — since 2026.07 the dataset ships Vauxhall
      # and Opel as separate makes (deliberately: separate GB/EU model names),
      # and an alias here would shadow the real Vauxhall records.
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

      # Name-alphabetical, diacritic-insensitive — the dataset file arrives
      # slug-sorted, which differs subtly ("Austin-Healey" vs "Austin Morris").
      @makes    = (raw["makes"] || []).map { |attrs| Make.new(attrs) }
                                      .sort_by { |m| Vehicles.normalize(m.name) }
      @by_slug  = {}   # raw slug => Make
      @index    = {}   # normalized (ASCII-folded) name/slug/alias => Make
      @exact    = {}   # downcased exact string => Make — for non-Latin aliases
      # (比亚迪, ヤマハ, 현대) that fold to "" under normalize
      @makes.each do |make|
        @by_slug[make.slug] = make
        index(make.name, make)
        index(make.slug, make)
        make.aliases.each do |a|
          index(a, make)
          @exact[a.downcase] ||= make
        end
      end
    end

    # All makes, optionally filtered by kind and/or continent. `region:` is a
    # CONTINENT (:eu/:na/:as/:sa/:oc/:af) — a make matches if it's evidenced
    # there. (Legacy note: pre-1.0 `region:` meant "does the snapshot cover
    # this?"; on today's global snapshot both readings return European makes
    # for `region: :eu`, so existing callers are unaffected.) An unmapped
    # continent honestly returns [].
    def makes(kind: nil, region: nil)
      list = @makes
      list = list.select { |m| m.kinds.include?(kind.to_sym) } if kind
      list = list.select { |m| m.in_region?(region) }          if region
      list
    end

    # Resolve a make from a String/Symbol/Make via aliases, slug, or name.
    def find_make(query)
      return query if query.is_a?(Make)

      q = Vehicles.normalize(query)
      # Non-Latin queries (比亚迪, 현대) fold to "" — try the exact index first.
      return @exact[query.to_s.strip.downcase] if q.empty?

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

    # Flat list of every Model (memoized + frozen — shared, so don't let callers
    # mutate it). Backs `search`.
    def all_models
      @all_models ||= @makes.flat_map(&:models).freeze
    end

    # Every kind present in the snapshot. => [:bus, :car, :moped, ...]
    def kinds
      @kinds ||= @makes.flat_map(&:kinds).uniq.sort.freeze
    end

    # Ranked models by popularity: global decile first, then breadth of
    # availability as the tiebreaker, then name. Unranked models (nil decile —
    # catalog-only evidence) never appear: "unknown" must not outrank "known".
    #   top_models(kind: :car, country: :nl, limit: 10)
    #   top_models(kind: :motorcycle, region: :as, limit: 10)  # by continent
    def top_models(kind: nil, country: nil, region: nil, limit: 20)
      c = country&.to_s&.downcase
      list = all_models.select(&:global_decile)
      list = list.select { |m| m.kind == kind.to_sym } if kind
      list = list.select { |m| m.availability.include?(c) } if c
      list = list.select { |m| m.available_in_region?(region) } if region
      list.sort_by { |m| [m.global_decile, -m.availability.size, m.name] }.first(limit)
    end

    # Every model matching optional kind/region/rarity filters, ranked by
    # popularity. The "give me a sensible slice" entry point.
    def all_models_filtered(kind: nil, region: nil, rarity: nil, max_decile: nil)
      list = all_models
      list = list.select { |m| m.kind == kind.to_sym }          if kind
      list = list.select { |m| m.available_in_region?(region) } if region
      list = list.select { |m| m.rarity == rarity.to_sym }      if rarity
      list = list.select { |m| m.global_decile && m.global_decile <= max_decile } if max_decile
      list
    end

    # Does this snapshot cover the given region? A "global" snapshot covers
    # every region, so callers pinned to `region: :eu` keep working as the
    # dataset outgrows Europe.
    def region?(region)
      region_match?(region)
    end

    private

    def index(key, make)
      @index[Vehicles.normalize(key)] ||= make
    end

    def region_match?(region)
      Vehicles.normalize(@region) == "global" ||
        Vehicles.normalize(region) == Vehicles.normalize(@region)
    end
  end
end
