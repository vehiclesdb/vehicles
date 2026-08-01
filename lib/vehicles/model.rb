# frozen_string_literal: true

module Vehicles
  # A single vehicle nameplate, e.g. "Volkswagen Golf". A lightweight, immutable
  # value object — no ActiveRecord, no mutation. Reads like English on purpose.
  #
  #   car = Vehicles.find("vw golf")
  #   car.make        # => "Volkswagen"
  #   car.name        # => "Golf"
  #   car.full_name   # => "Volkswagen Golf"
  #   car.body_type   # => :hatchback
  #   car.suv?        # => false
  class Model
    # Vehicle kinds (RDW `voertuigsoort`). Today the bundled data is all :car;
    # the shape already supports the rest for when those packs land.
    KINDS = %i[car motorcycle van truck pickup trailer bus moped quad trike].freeze

    # Body types — the sub-classification within a kind. For cars these are the
    # familiar shapes; motorcycle styles (:naked, :adventure, …) reuse this field.
    BODY_TYPES = %i[
      hatchback sedan wagon suv mpv coupe convertible roadster pickup van
    ].freeze

    # Continent codes (the model `regions` rollup). Order = rough market size.
    REGIONS = %i[eu na as sa oc af].freeze

    attr_reader :make, :make_slug, :name, :kind, :body_type, :global_decile,
                :availability, :regions, :aliases, :former_ids

    # @param attrs [Hash] one model entry from the dataset (name/slug/kind +
    #   optional body_type/global_decile/availability/regions/aliases/former_ids)
    # @param make [String] the parent make's display name
    # @param make_slug [String] the parent make's slug (for the composite slug)
    def initialize(attrs, make:, make_slug:)
      @make       = make
      @make_slug  = make_slug
      @name       = attrs["name"]
      @model_slug = attrs["slug"]
      @kind       = (attrs["kind"] || "car").to_sym
      # nil = no body vocabulary for this record yet (most non-car kinds).
      # A default would be a lie — predicates just return false instead.
      @body_type  = attrs["body_type"]&.to_sym
      # Popularity decile 1 (most popular) … 10, averaged over every country
      # with registration counts. nil = catalog-only evidence, no counts yet.
      @global_decile = attrs["global_decile"]
      # ISO-3166-1 alpha-2 codes where an official source evidences the model.
      # Evidence of PRESENCE, not proof of official marketing (grey imports
      # count — they're real vehicles on real roads).
      @availability  = (attrs["availability"] || []).freeze
      # Continent rollup of availability (:eu/:na/:sa/:as/:oc/:af).
      @regions       = (attrs["regions"] || []).map(&:to_sym).freeze
      # Documented alternate names (nicknames, native scripts, market names).
      @aliases       = (attrs["aliases"] || []).freeze
      # Full canonical ids ("car/alfa-romeo/159sw") this record absorbed via
      # the dataset's append-only migration contract (SCHEMA.md: renames
      # alias, nothing is silently deleted). Empty for never-renamed records.
      @former_ids    = (attrs["former_ids"] || []).freeze
      freeze
    end

    # "Volkswagen Golf" — the natural label for a model on its own.
    def full_name
      "#{make} #{name}"
    end
    alias to_s full_name

    # Composite, stable slug: "volkswagen-golf".
    def slug
      "#{make_slug}-#{@model_slug}"
    end

    # The bare model slug ("golf"), used as the value in `model_options`.
    attr_reader :model_slug

    # Predicate sugar: `car.suv?`, `car.hatchback?`, `car.car?`, `car.motorcycle?`.
    # `pickup?`/`van?` are true whether the term is the kind or the body type.
    (KINDS | BODY_TYPES).each do |type|
      define_method("#{type}?") { [@kind, @body_type].include?(type) }
    end

    # Motorcycle OR moped — the union pickers usually want ("two-wheeler
    # section" in an insurance/marketplace form).
    def two_wheeler?
      %i[motorcycle moped].include?(@kind)
    end

    # Evidence of presence in a country (see `availability` for semantics):
    #   Vehicles.find("vw golf").available_in?(:nl)  # => true
    def available_in?(country)
      availability.include?(country.to_s.downcase)
    end

    # Evidence of presence on a continent (:eu/:na/:sa/:as/:oc/:af):
    #   Vehicles.find("perodua myvi").available_in_region?(:as)  # => true
    def available_in_region?(region)
      regions.include?(region.to_sym)
    end

    # Continent predicate sugar: `.european?`, `.asian?`, `.north_american?`,
    # `.south_american?`, `.oceanian?`, `.african?`.
    { european: :eu, north_american: :na, asian: :as,
      south_american: :sa, oceanian: :oc, african: :af }.each do |word, code|
      define_method("#{word}?") { @regions.include?(code) }
    end

    # Top-20% popularity across covered markets. false when unranked (nil
    # decile) — "we don't know" must never read as "popular".
    def popular?
      !global_decile.nil? && global_decile <= 2
    end

    # Rarity tier from the popularity decile — the coarse "how much data do I
    # want to show" knob. Deciles are the moat's measured signal; this buckets
    # them into three names apps can filter on WITHOUT us exposing raw counts:
    #   :common  deciles 1-3   (the names everyone knows — safe default filter)
    #   :average deciles 4-7
    #   :rare    deciles 8-10
    #   :unknown unranked (catalog-only evidence — no popularity signal yet)
    def rarity
      return :unknown if global_decile.nil?
      return :common  if global_decile <= 3
      return :average if global_decile <= 7

      :rare
    end

    def common?  = rarity == :common
    def rare?    = rarity == :rare

    def to_h
      { make: make, model: name, slug: slug, kind: kind, body_type: body_type,
        global_decile: global_decile, rarity: rarity,
        availability: availability, regions: regions, aliases: aliases,
        former_ids: former_ids }
    end

    # Value-object equality — two models with the same slug are equal.
    def ==(other)
      other.is_a?(Model) && other.slug == slug
    end
    alias eql? ==

    def hash
      slug.hash
    end

    def inspect
      %(#<Vehicles::Model "#{full_name}" #{body_type || kind}>)
    end

    # --- Hosted VehiclesDB data (optional) -----------------------------------
    # These resolve through the provider chain: the hosted API answers when an
    # api_key is configured, otherwise they degrade to the local data (nil today).
    # They NEVER raise — a missing/slow API just yields nil and your view renders
    # a placeholder. See Vehicles::Providers.

    # Production years as a Range, e.g. 1974..2024. nil without hosted data.
    def years
      Vehicles.resolve(:years, self)
    end

    # Editorial market segment, e.g. :hot_hatch, :supercar. nil without hosted data.
    def segment
      Vehicles.resolve(:segment, self)
    end

    # One rendered image URL, ready for an <img src>. `size` picks the
    # variant (:sm/:md/:lg), `color` a palette slug (Vehicles.colors); an
    # un-rendered color falls back honestly server-side rather than erroring.
    # `year` is accepted for forward-compatibility but not yet served.
    # nil without hosted data — always render a placeholder path.
    def image(year: nil, color: nil, size: :md)
      Vehicles.resolve(:image, self, year: year, color: color, size: size)
    end

    # The full hosted images payload — every variant with dimensions, the
    # rendered palette for this model, served-vs-requested color, provenance.
    # Reach for this when one URL isn't enough (srcset, color pickers,
    # caching whole responses). nil without hosted data.
    def images(color: nil)
      Vehicles.resolve(:images, self, color: color)
    end
  end
end
