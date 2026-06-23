# frozen_string_literal: true

module Vehicles
  # The single source of truth for every knob. Sensible defaults mean you can use
  # the whole gem without ever touching this — `Vehicles.configure` is opt-in.
  #
  #   Vehicles.configure do |config|
  #     config.region  = :eu
  #     config.api_key = ENV["VEHICLESDB_API_KEY"]
  #     config.aliases = { "Chevy" => "Chevrolet" }
  #   end
  class Configuration
    # Default region for queries. Today the bundled data ships :eu; the API is
    # already region-aware so :us/:gb/etc. are additive, never breaking.
    attr_accessor :region

    # Optional VehiclesDB API key. When set, the hosted provider activates and
    # enriches models with years/images/segments. When nil, everything still
    # works on the bundled data — the gem is standalone first, SDK second.
    attr_accessor :api_key

    # Base URL for the hosted VehiclesDB API. Overridable for self-hosting/testing.
    attr_accessor :api_base_url

    # Network timeout (seconds) for hosted API calls. Kept short so a slow/missing
    # API never blocks a request — hosted lookups degrade to the local data.
    attr_accessor :api_timeout

    # Extra make aliases, merged over the built-in ones. Keys are matched
    # forgivingly (case/diacritics-insensitive); values are canonical make names.
    attr_reader :aliases

    def initialize
      @region       = :eu
      @api_key      = nil
      @api_base_url = "https://api.vehiclesdb.org"
      @api_timeout  = 2
      @aliases      = {}
    end

    # Normalize alias keys at assignment time so lookups stay O(1) and forgiving.
    def aliases=(hash)
      @aliases = (hash || {}).each_with_object({}) do |(k, v), memo|
        memo[Vehicles.normalize(k)] = v.to_s
      end
    end
  end
end
