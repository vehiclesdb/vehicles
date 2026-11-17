# frozen_string_literal: true

module Vehicles
  # A vehicle make, e.g. "Volkswagen", and the models it builds. Immutable value
  # object. Its models are built lazily once and cached.
  #
  #   make = Vehicles.make("Audi")
  #   make.slug       # => "audi"
  #   make.models     # => ["A3", "A4", "Q3", ...]
  #   make.model("a3")# => #<Vehicles::Model "Audi A3">
  class Make
    # "Serie 3" — how BMW sells the 3 Series in Spain and Italy (and "Série"
    # in France, which normalizes the same) — read as "3 Series".
    LOCALIZED_SERIES = /\Aserie (\w+)\z/

    # The per-make lookup tables behind #model and Vehicles.match_model
    # (normalized key => models in dataset order); see #build_lookup_index.
    TABLES = %i[name name_squeezed slug alias alias_squeezed alias_raw form form_squeezed].freeze

    attr_reader :name, :slug, :aliases, :kinds, :former_slugs

    def initialize(attrs)
      @name    = attrs["name"]
      @slug    = attrs["slug"]
      @aliases = Array(attrs["aliases"]).freeze
      @kinds   = Array(attrs["kinds"]).map(&:to_sym).freeze
      # Slugs this make was published under before a rename or merge
      # (dataset key `former_slugs`, when the dataset publishes it; [] until
      # then). Vehicles.make and Vehicles.by_id follow them.
      @former_slugs = Array(attrs["former_slugs"]).map(&:to_s).freeze
      @raw_models = attrs["models"] || []
    end

    # All models for this make, optionally filtered by kind/body_type/region/
    # rarity. Returns Vehicles::Model objects, ordered by popularity (as built).
    # The unfiltered list is memoized AND frozen — it's shared process-wide, so a
    # frozen array turns accidental caller mutation into a loud error instead of
    # silently corrupting the dataset. Filtered calls return a fresh array.
    #   models(kind: :car, region: :eu)          # European cars only
    #   models(rarity: :common)                  # just the well-known ones
    #   models(max_decile: 3)                     # top-30% by popularity
    def models(kind: nil, body_type: nil, region: nil, rarity: nil, max_decile: nil, country: nil)
      list = (@models ||= @raw_models.map { |m| Model.new(m, make: name, make_slug: slug) }.freeze)
      list = list.select { |m| m.kind == kind.to_sym }             if kind
      list = list.select { |m| m.body_type == body_type.to_sym }   if body_type
      list = list.select { |m| m.available_in_region?(region) }    if region
      list = by_popularity(list, rarity, max_decile)
      country ? by_country(list, country) : list
    end

    # Continents this make is evidenced in (union of its models' regions).
    # => [:eu, :as, :na] — powers make-level continent filtering.
    def continents
      @continents ||= models.flat_map(&:regions).uniq.freeze
    end

    # Is this make evidenced on the given continent? (:eu/:na/:as/:sa/:oc/:af)
    def in_region?(region)
      continents.include?(region.to_sym)
    end

    # Does any of its models (of `kind`) have evidence in this country?
    def available_in?(country, kind: nil)
      models(kind: kind).any? { |m| m.available_in?(country) }
    end

    # Model display names — what you drop into a dropdown. => ["A3", "A4", ...]
    def model_names(**filters)
      models(**filters).map(&:name)
    end

    # [[label, value], ...] for Rails `select`. => [["A3", "a3"], ["A4", "a4"]]
    def model_options(**filters)
      models(**filters).map { |m| [m.name, m.model_slug] }
    end

    # Find one model within this make by name or slug. Forgiving about case,
    # accents and spacing — "a3", "A 3", "XCeed" (the dataset's "X Ceed") and
    # BMW's Spanish "Serie 3" (→ "3 Series") all resolve — but partial input
    # does NOT (so `model("a")` returns nil, not "A3" — important, since the
    # vehicle_model validator relies on this). Fuzzy/partial matching lives in
    # `Vehicles.search`.
    #
    # Some names exist as several kinds (Iveco "Daily" is a van, a truck and
    # a bus). Without a kind the one collision rule decides (Vehicles::KindRule;
    # until 0.9.1 the car always won). Pass `kind:` to pick
    # one, or `kinds:` to allow only some:
    #   iveco.model("Daily")              # => the van
    #   iveco.model("Daily", kind: :bus)  # => the bus
    #   iveco.model("Daily", kinds: %i[car]) # => nil (no car Daily)
    def model(query, kind: nil, kinds: nil)
      matches, how = strict_lookup(Vehicles.normalize(query), kind: KindRule.scope(kind, kinds))
      matches && how != :ambiguous ? pick(matches) : nil
    end

    # --- internal lookup surface (ModelMatcher) ------------------------------
    # Not part of the public API: the pieces `model` and Vehicles.match_model
    # share, so the strict rung of match_model can never drift from `model`.

    # The strict lookup behind #model on an already-normalized query:
    # [matches, how] where how is :name (exact name/slug), :spacing (same
    # letters and digits, spacing ignored) or :series ("Serie 3"), or
    # [nil, nil] when nothing answers. A spacing-blind hit that lands on two
    # different names is reported as [those models, :ambiguous] — #model
    # treats that as nil, exactly as before 0.9.0.
    def strict_lookup(query, kind: nil)
      return [nil, nil] if query.empty?

      found = named(query, kind)
      return found if found.first

      series = query.sub(LOCALIZED_SERIES, '\\1 series')
      if series != query
        hit, how = named(series, kind)
        return [hit, how == :name ? :series : how] if hit
      end
      found
    end

    # The models whose published alias (field :alias) or curated registry
    # spelling (field :form) is this normalized query — normalized equality
    # first, then spacing-blind. May span several model slugs: the caller
    # decides what that means (ModelMatcher reports it as ambiguous).
    # Returns [models, :exact | :spacing] or [[], nil].
    def curated_lookup(field, query, kind: nil)
      exact = of_kind(lookup_index[field][query], kind)
      return [exact, :exact] if exact.any?

      loose = of_kind(lookup_index[:"#{field}_squeezed"][query.delete(" ")], kind)
      loose.any? ? [loose, :spacing] : [[], nil]
    end

    # Non-Latin model aliases (e.g. a native-script nameplate) fold to "" under
    # normalize, so they are kept by their downcased raw text instead.
    def raw_alias_lookup(raw, kind: nil)
      of_kind(lookup_index[:alias_raw][raw.to_s.strip.downcase], kind)
    end

    # [[normalized key, model], ...] over every name, published alias and
    # curated form of this make — the haystack for the model typo rung.
    def typo_keys
      lookup_index[:typo_keys]
    end

    # Is this normalized string a complete model name, slug or published alias
    # of this make? Cleanup never peels such a token off the front: "Nova SS"
    # is a Chevrolet Nova, not an "SS" with a "new" in front.
    def model_word?(key)
      idx = lookup_index
      idx[:name].key?(key) || idx[:alias].key?(key) || idx[:slug].key?(key)
    end

    # One record among kind variants of a nameplate: Vehicles::KindRule.
    def pick(matches)
      KindRule.pick(matches)
    end

    def to_h
      { name: name, slug: slug, kinds: kinds, models: model_names }
    end

    def to_s
      name
    end

    def ==(other)
      other.is_a?(Make) && other.slug == slug
    end
    alias eql? ==

    def hash
      slug.hash
    end

    def inspect
      %(#<Vehicles::Make "#{name}">)
    end

    private

    # The models answering to a normalized query: by exact name or slug; failing
    # that, by the same letters and digits with spacing ignored ("xceed" is
    # "X Ceed", "a 5" is "A5") — but only when that lands on ONE name, never a
    # guess between two. [matches, how], or [nil, nil] when nothing answers.
    #
    # Index-backed since 0.9.0 (it used to normalize every model name on every
    # call — the dominant cost of bulk lookups). Results keep dataset order,
    # since `pick` falls back to the FIRST match when no car is among them.
    def named(query, kind)
      idx = lookup_index
      exact = of_kind(in_order(idx[:name][query], idx[:slug][query]), kind)
      return [exact, :name] if exact.any?

      loose = of_kind(idx[:name_squeezed][query.delete(" ")], kind)
      return [nil, nil] if loose.empty?
      # One NAMEPLATE (model slug) in several kinds is a kind collision, not
      # ambiguity, even when a release styles the kinds' names differently.
      return [loose, :spacing] if loose.map(&:model_slug).uniq.one?

      [loose, :ambiguous]
    end

    # `kind` is nil (any), one kind, or a list of allowed kinds.
    def of_kind(list, kind)
      list ||= []
      allowed = KindRule.symbols(kind)
      allowed ? list.select { |m| allowed.include?(m.kind) } : list
    end

    def by_popularity(list, rarity, max_decile)
      list = list.select { |m| m.rarity == rarity.to_sym } if rarity
      list = list.select { |m| m.global_decile && m.global_decile <= max_decile } if max_decile
      list
    end

    # A country's own ranking first (Model#rank_in), then the make's order.
    def by_country(list, country)
      c = country.to_s.downcase
      list.select { |m| m.availability.include?(c) }
          .each_with_index.sort_by { |m, i| [m.rank_in(c) ? 0 : 1, m.rank_in(c) || 0, i] }.map(&:first)
    end

    # Union of two index hits, deduplicated by identity and put back in
    # dataset order.
    def in_order(first, second)
      return first || [] unless second
      return second unless first

      pos = lookup_index[:position]
      (first + second).uniq(&:object_id).sort_by { |m| pos[m] }
    end

    # Every per-make lookup table, built once on first use. Keys are
    # normalized strings; values are arrays of models in dataset order.
    def lookup_index
      @lookup_index ||= build_lookup_index
    end

    def build_lookup_index
      idx = TABLES.to_h { |t| [t, Hash.new { |h, k| h[k] = [] }] }
      idx.merge!(position: {}.compare_by_identity, normalized: {}.compare_by_identity, typo_keys: [])
      models.each_with_index { |model, i| index_model(idx, model, i) }
      # Drop the auto-vivifying defaults: a miss must read nil, not grow the table.
      TABLES.each { |t| idx[t].default_proc = nil }
      idx[:typo_keys] = idx[:typo_keys].uniq { |key, model| [key, model.object_id] }.freeze
      idx.freeze
    end

    def index_model(idx, model, position)
      name = Vehicles.normalize(model.name)
      idx[:position][model] = position
      idx[:normalized][model] = name
      idx[:name][name] << model
      idx[:name_squeezed][name.delete(" ")] << model
      idx[:slug][model.model_slug] << model
      idx[:typo_keys] << [name, model] unless name.empty?
      index_curated(idx, :alias, model.aliases, model)
      index_curated(idx, :form, model.forms, model)
    end

    def index_curated(idx, field, values, model)
      values.each do |value|
        key = Vehicles.normalize(value)
        if key.empty?
          idx[:alias_raw][value.to_s.strip.downcase] << model if field == :alias
          next
        end
        idx[field][key] << model
        idx[:"#{field}_squeezed"][key.delete(" ")] << model
        idx[:typo_keys] << [key, model]
      end
    end
  end
end
