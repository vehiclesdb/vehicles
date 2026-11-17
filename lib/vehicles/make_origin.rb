# frozen_string_literal: true

module Vehicles
  # A make's country of origin (dataset 2026.11.10+, SCHEMA.md "Country of
  # origin"), kept apart from Make's lookup code:
  #
  #   Vehicles.make("BMW").country                   # => "de"
  #   Vehicles.make("BMW").country_tier              # => "manufacturer"
  #   Vehicles.make("Leyland DAF").country_disputed  # => ["gb", "nl"]
  #   Vehicles.make("Leyland DAF").origin_countries  # => ["gb", "nl"]
  #
  # `country` is where the MARQUE WAS FOUNDED, as a lower-case ISO 3166-1
  # alpha-2 code: not where it is built, not its headquarters, not its
  # owner's country (MG is "gb"). nil means "not catalogued yet", never
  # "unknown" or "none". `country_tier` says what it rests on
  # ("manufacturer", "regulator" or "archive") and is present exactly when
  # `country` is. A marque whose founding spans two countries has no
  # `country` and lists the candidates in `country_disputed`; [] otherwise.
  module MakeOrigin
    attr_reader :country, :country_tier, :country_disputed

    def initialize(attrs)
      super
      @country          = attrs["country"]&.to_s&.freeze
      @country_tier     = attrs["country_tier"]&.to_s&.freeze
      @country_disputed = Array(attrs["country_disputed"]).map(&:to_s).freeze
    end

    # Every country this marque counts as founded in: [country], the
    # disputed candidates, or [] when the dataset has not catalogued it.
    def origin_countries
      country ? [country] : country_disputed
    end
  end

  Make.prepend(MakeOrigin)
end
