# frozen_string_literal: true

module Vehicles
  # The single source of truth for every knob. Sensible defaults mean you can use
  # the whole gem without ever touching this — `Vehicles.configure` is opt-in.
  #
  #   Vehicles.configure do |config|
  #     config.region  = :eu   # optional default continent filter
  #     config.api_key = ENV["VEHICLESDB_API_KEY"]
  #     config.aliases = { "Chevy" => "Chevrolet" }
  #   end
  class Configuration
    # Optional default CONTINENT filter for make/model queries
    # (:eu/:na/:as/:sa/:oc/:af). nil (the default) means "no filter — the whole
    # global dataset". Set it to scope an app to one market without passing
    # `region:` on every call. (Pre-1.0 this defaulted to :eu when the data
    # was EU-only; the global dataset makes "everything" the honest default.)
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

    # Label for the "Other / not in the list" escape-hatch option, used by the
    # `include_other:` helpers and the `allow_other:` validators. Defaults to
    # "Other"; set it to your UI language (e.g. "Otro", "Autre") so the option
    # reads naturally. Matching is forgiving: the canonical slug "other" is always
    # accepted too, so a stored "Other" validates even if you later relabel it.
    attr_accessor :other_label

    # --- data refresh (optional) ---------------------------------------------
    # The gem ships a bundled snapshot that works offline with zero setup. These
    # let an app pull the latest published dataset (e.g. via a daily job) so data
    # fixes and new makes land WITHOUT a gem upgrade.

    # Where `Vehicles.refresh!` pulls the latest dataset. Defaults to the public
    # VehiclesDB data repo via jsDelivr's CDN (always-latest release tag).
    attr_accessor :data_url

    # Where a refreshed dataset is cached on disk. Defaults to the app's cache dir
    # (Rails) or the system temp dir. The refresh writes here; loads prefer it.
    attr_accessor :cache_path

    # Prefer a refreshed (cached) dataset over the bundled one when present.
    # Set false to always use the bundled snapshot (fully offline/deterministic).
    attr_accessor :use_cache

    # Network timeout (seconds) for a refresh download.
    attr_accessor :refresh_timeout

    def initialize
      @region          = nil # no continent filter by default (global dataset)
      @api_key         = nil
      @api_base_url    = "https://api.vehiclesdb.com"
      @api_timeout     = 2
      @aliases         = {}
      @other_label     = "Other"
      @data_url        = "https://cdn.jsdelivr.net/gh/vehiclesdb/vehiclesdb@latest/dist/vehicles.json"
      @cache_path      = default_cache_path
      @use_cache       = true
      @refresh_timeout = 5
    end

    # Normalize alias keys at assignment time so lookups stay O(1) and forgiving.
    def aliases=(hash)
      @aliases = (hash || {}).each_with_object({}) do |(k, v), memo|
        memo[Vehicles.normalize(k)] = v.to_s
      end
    end

    private

    # tmp/cache/vehicles under a Rails app, else a stable spot in the system temp
    # dir. Refreshable data, so a cache-style location is appropriate.
    def default_cache_path
      base =
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join("tmp", "cache", "vehicles")
        else
          require "tmpdir"
          File.join(Dir.tmpdir, "vehicles")
        end
      File.join(base.to_s, "vehicles.json")
    end
  end
end
