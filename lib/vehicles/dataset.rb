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
    include DatasetResolution

    # Built-in make aliases — EMPTY since 0.9.0, kept only so code that
    # references the constant does not break. RESOLUTION.md §1 ("only
    # published data counts"): a Ruby-only table made "Landrover Discovery"
    # resolve here and nowhere else (JS/Python SDKs, the API, the widget).
    # Every nickname that lived here (vw, vdub, merc, mercedes, benz, mb,
    # chevy, beemer, bimmer, alfa, landrover) is now a PUBLISHED make alias in
    # the dataset (overrides/makes/search_aliases.yml, data 2026.11.0), so all
    # surfaces agree. "range rover"/"rangerover" were dropped, not published:
    # Range Rover is a Land Rover model family, not a make ("Range Rover
    # Defender" is not a vehicle). Need a private nickname? Use
    # `config.aliases`, which stays yours alone by design.
    BUILTIN_ALIASES = {}.freeze

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

    attr_reader :version, :schema_version, :region, :license, :attribution

    def initialize(raw)
      @version        = raw["version"]
      @schema_version = raw["schema_version"]
      @region         = raw["region"]
      # The licence id and the credit block the release publishes (CC-BY
      # 4.0), carried into Vehicles.dataset_slice so a slice keeps them.
      @license        = raw["license"]
      @attribution    = raw["attribution"]

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
      index_former_slugs
    end

    # The make that now carries a retired make slug ("mg-roewe" → MG), or nil.
    def make_by_former_slug(slug)
      @by_former_slug[slug.to_s]
    end

    # All makes, optionally filtered by kind and/or continent. `region:` is a
    # CONTINENT (:eu/:na/:as/:sa/:oc/:af) — a make matches if it's evidenced
    # there. (Legacy note: pre-1.0 `region:` meant "does the snapshot cover
    # this?"; on today's global snapshot both readings return European makes
    # for `region: :eu`, so existing callers are unaffected.) An unmapped
    # continent honestly returns [].
    def makes(kind: nil, region: nil, country: nil)
      list = @makes
      list = list.select { |m| m.kinds.include?(kind.to_sym) } if kind
      list = list.select { |m| m.in_region?(region) }          if region
      list = list.select { |m| m.available_in?(country, kind: kind) } if country
      list
    end

    # Resolve a make from a String/Symbol/Make via aliases, slug, or name.
    # With `fuzzy:` (the default), a query that matches nothing exactly falls
    # back to the closest make by edit distance — "marcedes" → Mercedes-Benz —
    # but only when ONE make is strictly closest; equally close makes → nil.
    # Pass `fuzzy: false` where a typo must NOT count as a match (validators).
    def find_make(query, fuzzy: true)
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
      # 4. bounded edit-distance fallback over names/slugs/aliases (Fuzzy);
      #    user-configured aliases are not fuzzy-matched
      #    — never for the "Other" escape hatch's label ("Otra" is one edit
      #    from the make Ora; Vehicles.models("Otra", include_other: true)
      #    must stay [other_label])
      #    — and never for id/slug/path-shaped input (Fuzzy.eligible_input?)
      fuzzy &&= Fuzzy.eligible_input?(query) && !Vehicles.other?(query)
      @by_slug[q] || @index[q] || (fuzzy ? Fuzzy.unique_closest(q, fuzzy_keys) : nil)
    end

    # Resolve a free-text "make + model" string into one Model. Tries the longest
    # leading make prefix first ("land rover defender"), then the remainder as the
    # model. Returns nil if nothing matches.
    #
    # The exact pass runs first over EVERY split; only if nothing matches is
    # the make prefix retried with typo tolerance, so no answer that resolved
    # before 0.7.8 can change ("volkswagon golf" now resolves; "vw golf" is
    # answered by the exact pass exactly as before).
    def find_model(query, fuzzy: true)
      q = Vehicles.normalize(query)
      tokens = q.split
      return nil if tokens.empty?

      fuzzy &&= Fuzzy.eligible_input?(query) # ids/slugs/paths resolve exactly or not at all
      model_by_split(tokens, fuzzy: false) || (fuzzy ? model_by_split(tokens, fuzzy: true) : nil)
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

    # Continent codes present in the snapshot. => [:af, :as, :eu, ...]
    def regions
      @regions ||= all_models.flat_map(&:regions).uniq.sort.freeze
    end

    # Every kind present in the snapshot. => [:bus, :car, :moped, ...]
    def kinds
      @kinds ||= @makes.flat_map(&:kinds).uniq.sort.freeze
    end

    # Ranked models by popularity. Unranked models (nil decile — catalog-only
    # evidence) never appear: "unknown" must not outrank "known".
    #
    # Without `country:` — global decile, then breadth of availability, then
    # name. WITH `country:` — that country's OWN rank (Model#rank_in) first,
    # so a UK list reads in UK order, not in the presence-weighted global
    # order (until 0.7.7 a filtered list kept the global sort). Models
    # available there but without a rank there follow, in global order; a
    # snapshot without `country_ranks` (data before 2026.10) degrades to the
    # 0.7.7 order. Ranks are per KIND, so pass `kind:` for a clean ranking —
    # without it, kinds interleave by rank (car #1, motorcycle #1, …).
    #
    # `by:` picks the decile: :global_decile (default — presence average,
    # "popular in many places") or :mass_decile (per-kind registration mass,
    # "how many exist"; data 2026.10.1+). Records without the chosen decile
    # never appear, so `by: :mass_decile` on an older snapshot returns [].
    #   top_models(kind: :car, country: :gb, limit: 10)
    # With `country:`, the country's own rank still sorts first and the
    # chosen decile only breaks ties among models ranked equally there.
    #   top_models(kind: :car, by: :mass_decile, limit: 10)
    #   top_models(kind: :motorcycle, region: :as, limit: 10)  # by continent
    # `limit: nil` returns every match.
    def top_models(kind: nil, country: nil, region: nil, limit: 20, by: :global_decile)
      raise ArgumentError, "by: must be :global_decile or :mass_decile" unless RANKINGS.include?(by)

      c = country&.to_s&.downcase
      list = all_models.select(&by)
      list = list.select { |m| m.kind == kind.to_sym } if kind
      list = list.select { |m| m.availability.include?(c) } if c
      list = list.select { |m| m.available_in_region?(region) } if region
      sorted = list.sort_by { |m| popularity_key(m, c, by) }
      limit ? sorted.first(limit) : sorted
    end

    RANKINGS = %i[global_decile mass_decile].freeze

    def popularity_key(model, country, by)
      rank = country && model.rank_in(country)
      [rank ? 0 : 1, rank || 0, model.public_send(by), -model.availability.size, model.name]
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

    # Former make slugs (a renamed or merged make) answer last: a current
    # name, slug or alias always wins over a retired slug.
    def index_former_slugs
      @by_former_slug = {}
      @makes.each do |make|
        make.former_slugs.each do |old|
          @by_former_slug[old] ||= make
          index(old, make)
        end
      end
    end

    def index(key, make)
      @index[Vehicles.normalize(key)] ||= make
    end

    # The longest-make-prefix split behind #find_model, one pass.
    def model_by_split(tokens, fuzzy:)
      (tokens.length - 1).downto(1) do |i|
        make = find_make(tokens[0, i].join(" "), fuzzy: fuzzy)
        next unless make

        model = make.model(tokens[i..].join(" "))
        return model if model
      end
      nil
    end

    # Every normalized key a make answers to (name, slug, published aliases,
    # built-in aliases) — the haystack for #fuzzy_make. Built once.
    def fuzzy_keys
      @fuzzy_keys ||= begin
        keys = @index.to_a
        BUILTIN_ALIASES.each { |key, slug| keys << [key, @by_slug[slug]] if @by_slug[slug] }
        keys.reject { |k, _m| k.empty? }.freeze
      end
    end

    def region_match?(region)
      Vehicles.normalize(@region) == "global" ||
        Vehicles.normalize(region) == Vehicles.normalize(@region)
    end
  end
end
