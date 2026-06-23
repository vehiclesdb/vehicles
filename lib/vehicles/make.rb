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

    # All models for this make, optionally filtered by kind/body_type.
    # Returns Vehicles::Model objects, ordered by popularity (as built).
    def models(kind: nil, body_type: nil)
      list = (@models ||= @raw_models.map { |m| Model.new(m, make: name, make_slug: slug) })
      list = list.select { |m| m.kind == kind.to_sym }           if kind
      list = list.select { |m| m.body_type == body_type.to_sym } if body_type
      list
    end

    # Model display names — what you drop into a dropdown. => ["A3", "A4", ...]
    def model_names(**filters)
      models(**filters).map(&:name)
    end

    # [[label, value], ...] for Rails `select`. => [["A3", "a3"], ["A4", "a4"]]
    def model_options(**filters)
      models(**filters).map { |m| [m.name, m.model_slug] }
    end

    # Find one model within this make by name, slug, or normalized text.
    # "a3" / "A3" / "Q 3" all resolve. Returns nil if not found.
    def model(query)
      q = Vehicles.normalize(query)
      return nil if q.empty?

      models.find { |m| Vehicles.normalize(m.name) == q || m.model_slug == q } ||
        models.find { |m| Vehicles.normalize(m.name).start_with?(q) }
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
