# frozen_string_literal: true

module Vehicles
  # A canonical vehicle color. Reference data, not RDW-derived: a small, stable
  # palette every consumer (and, in time, the hosted VehiclesDB image API) can
  # share, so "red" means the same thing — and maps to the same image variant —
  # everywhere. Display names are English; localize in your app (the slug is the
  # stable, locale-independent key you store; `label(:es)` gives the Spanish
  # one). `hex` is a representative swatch
  # for UI chips / future color-accurate imagery.
  class Color
    attr_reader :slug, :name, :hex

    def initialize(slug, name, hex)
      @slug = slug
      @name = name
      @hex  = hex
      freeze
    end

    # The display label in a locale (:en, :es; others fall back to English).
    #   Vehicles.color("red").label(:es)  # => "Rojo"
    def label(locale = :en)
      Labels.color(slug, locale) || name
    end

    def to_h
      { slug: slug, name: name, hex: hex }
    end

    def to_s
      name
    end

    def ==(other)
      other.is_a?(Color) && other.slug == slug
    end
    alias eql? ==

    def hash
      slug.hash
    end

    def inspect
      %(#<Vehicles::Color #{slug} "#{name}" #{hex}>)
    end
  end
end
