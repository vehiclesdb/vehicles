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

    attr_reader :make, :make_slug, :name, :kind, :body_type

    # @param attrs [Hash] one model entry from the dataset (name/slug/kind/body_type)
    # @param make [String] the parent make's display name
    # @param make_slug [String] the parent make's slug (for the composite slug)
    def initialize(attrs, make:, make_slug:)
      @make       = make
      @make_slug  = make_slug
      @name       = attrs["name"]
      @model_slug = attrs["slug"]
      @kind       = (attrs["kind"]      || "car").to_sym
      @body_type  = (attrs["body_type"] || "hatchback").to_sym
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

    def to_h
      { make: make, model: name, slug: slug, kind: kind, body_type: body_type }
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
      %(#<Vehicles::Model "#{full_name}" #{body_type}>)
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

    # Image URL, optionally year-/color-accurate. nil without hosted data.
    def image(year: nil, color: nil)
      Vehicles.resolve(:image, self, year: year, color: color)
    end
  end
end
