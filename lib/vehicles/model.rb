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
    # Vehicle kinds the predicates know (`car?`, `van?`, …). The data itself
    # publishes car, motorcycle, moped, van, truck and bus (Vehicles.kinds);
    # pickup/trailer/quad/trike are kept so existing predicate calls answer
    # false instead of raising.
    KINDS = %i[car motorcycle van truck pickup trailer bus moped quad trike].freeze

    # Body types — the sub-classification within a kind. For cars these are the
    # familiar shapes; motorcycle styles (:naked, :adventure, …) reuse this field.
    BODY_TYPES = %i[
      hatchback sedan wagon suv mpv coupe convertible roadster pickup van
    ].freeze

    # Continent codes (the model `regions` rollup). Order = rough market size.
    REGIONS = %i[eu na as sa oc af].freeze

    attr_reader :make, :make_slug, :name, :kind, :body_type, :global_decile,
                :availability, :regions, :aliases, :forms, :former_ids, :country_ranks, :mass_decile

    # @param attrs [Hash] one model entry from the dataset (name/slug/kind +
    #   optional body_type/global_decile/availability/regions/aliases/forms/former_ids)
    # @param make [String] the parent make's display name
    # @param make_slug [String] the parent make's slug (for the composite slug)
    def initialize(attrs, make:, make_slug:) # rubocop:disable Metrics/AbcSize -- one line per published field
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
      # Curated registry spellings that fold into this record ("Focus C-Max"
      # → C-Max, "Nuevo C4" → C4) — dataset key `forms`.
      # Unlike aliases they are not names anyone markets: they are how
      # registries and people actually TYPE the model, curated per make (never
      # ambiguous within a make, never equal to the name or an alias, and the
      # same on every kind's record of a make + slug). They power
      # Vehicles.model / Vehicles.match_model; [] on older snapshots.
      @forms         = (attrs["forms"] || []).freeze
      # Full canonical ids ("car/alfa-romeo/159sw") this record absorbed via
      # the dataset's append-only migration contract (SCHEMA.md: renames
      # alias, nothing is silently deleted). Empty for never-renamed records.
      @former_ids    = (attrs["former_ids"] || []).freeze
      # { "gb" => 2, "nl" => 1, ... } — the model's rank among every model of
      # its KIND in that country, from official registration counts (dataset
      # projection key `country_ranks`, data 2026.10+). Empty when unranked or
      # when the snapshot predates the key; `rank_in` then returns nil.
      @country_ranks = (attrs["country_ranks"] || {}).freeze
      # Per-KIND mass decile 1 (heaviest 10% by registrations summed across
      # measured countries) … 10 — "how many exist", where global_decile
      # (a presence average) answers "popular in many places". Published from
      # dataset 2026.10.1 (pipeline#255, ruling R3); nil on older snapshots
      # (including the bundled 2026.10.0) and for unranked records.
      @mass_decile = mass_decile_of(attrs)
      # The first and last year this nameplate appears in official
      # REGISTRATION data (dataset key `registration_years`), when published.
      # Not production or model years: grey imports and late registrations
      # widen it, and a register's coverage starts when its data does.
      @registration_years = registration_years_of(attrs)
      @id = id_of(make_slug)
      freeze
    end

    # The canonical VehiclesDB id, "car/volkswagen/golf" (RESOLUTION.md §1):
    # what to STORE. The same string the API, the SDKs and the widget use, and
    # what Vehicles.by_id / Vehicles.identify read back — including after a
    # dataset release renames the record (it lists the old id in former_ids).
    attr_reader :id

    # Years this nameplate shows up in official registrations, as a Range
    # (e.g. 1998..2026), or nil when the dataset does not publish them.
    # A HINT for ordering or pre-filling a year picker — never a validation
    # bound: an import, a late registration or a register that starts in 2015
    # all fall outside it legitimately. Not `years` (production years).
    attr_reader :registration_years

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

    # Rank in one country among all models of the same kind (1 = most
    # registered there), or nil when that country has no ranking for it.
    #   Vehicles.find("vw golf").rank_in(:gb)  # => 2
    def rank_in(country)
      country_ranks[country.to_s.downcase]
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
      { id: id, make: make, model: name, slug: slug, model_slug: model_slug, kind: kind, body_type: body_type,
        global_decile: global_decile, rarity: rarity,
        availability: availability, regions: regions, aliases: aliases, forms: forms,
        former_ids: former_ids, country_ranks: country_ranks, mass_decile: mass_decile,
        registration_years: registration_years && [registration_years.first, registration_years.last] }
    end

    # Value-object equality by canonical id (since 0.9.2). Until 0.9.1 it
    # compared the composite slug, so the car and the van of one nameplate
    # (Iveco Daily, Toyota Land Cruiser) were "equal" and collapsed in sets,
    # `uniq` and hash keys.
    def ==(other)
      other.is_a?(Model) && other.id == id
    end
    alias eql? ==

    def hash
      id.hash
    end

    def inspect
      %(#<Vehicles::Model "#{full_name}" #{body_type || kind}>)
    end

    # --- Hosted VehiclesDB data (optional) -----------------------------------
    # These resolve through the provider chain: the hosted API answers when an
    # api_key is configured, otherwise they degrade to the local data (nil today).
    # They NEVER raise — a missing/slow API just yields nil and your view renders
    # a placeholder. See Vehicles::Providers.

    # Production years as a Range, e.g. 1974..2024. Honest status: neither
    # the bundled data nor the hosted API publishes production years yet, so
    # this answers nil today (the seam lights up when the API serves them).
    # For a year-picker hint, see `registration_years`.
    def years
      Vehicles.resolve(:years, self)
    end

    # Editorial market segment, e.g. :hot_hatch, :supercar. nil without hosted data.
    def segment
      Vehicles.resolve(:segment, self)
    end

    # One rendered image URL, ready for an <img src>. `size` picks the
    # variant (:sm/:md/:lg), `color` a palette slug (Vehicles.colors); an
    # un-rendered color falls back honestly server-side (another color is
    # served) unless `exact_color: true`, which answers nil instead. `year`
    # is sent to the API, which rejects it until year-accurate renders ship
    # (→ nil; `images_result` says :invalid_request "unsupported_filter").
    # nil without hosted data or on any failure — always render a
    # placeholder path, and ask `images_result` when you need to know why.
    def image(year: nil, color: nil, size: :md, exact_color: false)
      Vehicles.resolve(:image, self, year: year, color: color, size: size, exact_color: exact_color)
    end

    # The full hosted images payload — every variant with dimensions, the
    # rendered palette for this model, served-vs-requested color, provenance.
    # Reach for this when one URL isn't enough (srcset, color pickers,
    # caching whole responses). nil without hosted data.
    def images(color: nil, year: nil, exact_color: false)
      Vehicles.resolve(:images, self, color: color, year: year, exact_color: exact_color)
    end

    # The same call as `images`, answering a Vehicles::HostedResult that says
    # WHY when there is no image (no key, 401/402/429, not rendered, timeout…).
    # Cached like `images`; never raises.
    def images_result(color: nil, year: nil, exact_color: false)
      Providers::HostedProvider.images_result(self, color: color, year: year, exact_color: exact_color)
    end

    private

    def id_of(make_slug) = "#{@kind}/#{make_slug}/#{@model_slug}".freeze

    def registration_years_of(attrs)
      years = attrs["registration_years"]
      first, last = years.is_a?(Hash) ? years.values_at("first", "last") : Array(years).first(2)
      first.is_a?(Integer) && last.is_a?(Integer) && first <= last ? (first..last) : nil
    end

    # The flat `mass_decile` key, or the nested `popularity.mass_decile` some
    # projections use.
    def mass_decile_of(attrs)
      pop = attrs["popularity"]
      attrs["mass_decile"] || (pop.is_a?(Hash) ? pop["mass_decile"] : nil)
    end
  end
end
