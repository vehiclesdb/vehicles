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
    attr_reader :name, :slug, :aliases, :kinds

    def initialize(attrs)
      @name    = attrs["name"]
      @slug    = attrs["slug"]
      @aliases = Array(attrs["aliases"]).freeze
      @kinds   = Array(attrs["kinds"]).map(&:to_sym).freeze
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
    def models(kind: nil, body_type: nil, region: nil, rarity: nil, max_decile: nil)
      list = (@models ||= @raw_models.map { |m| Model.new(m, make: name, make_slug: slug) }.freeze)
      list = list.select { |m| m.kind == kind.to_sym }             if kind
      list = list.select { |m| m.body_type == body_type.to_sym }   if body_type
      list = list.select { |m| m.available_in_region?(region) }    if region
      list = list.select { |m| m.rarity == rarity.to_sym }         if rarity
      list = list.select { |m| m.global_decile && m.global_decile <= max_decile } if max_decile
      list
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

    # Model display names — what you drop into a dropdown. => ["A3", "A4", ...]
    def model_names(**filters)
      models(**filters).map(&:name)
    end

    # [[label, value], ...] for Rails `select`. => [["A3", "a3"], ["A4", "a4"]]
    def model_options(**filters)
      models(**filters).map { |m| [m.name, m.model_slug] }
    end

    # Find one model within this make by exact (normalized) name or slug.
    # "a3" / "A3" / "Q 3" resolve; partial input does NOT (so `model("a")`
    # returns nil, not "A3" — important, since the vehicle_model validator relies
    # on this). Fuzzy/partial matching lives in `Vehicles.search`.
    def model(query)
      q = Vehicles.normalize(query)
      return nil if q.empty?

      models.find { |m| Vehicles.normalize(m.name) == q || m.model_slug == q }
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
  end
end
