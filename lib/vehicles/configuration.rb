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

    # Where the hosted VehiclesDB API lives — the ORIGIN, without the /api/v1
    # (endpoint paths carry it: HostedProvider::API_PREFIX). Overridable for
    # self-hosting, staging or a local server: "http://localhost:3030".
    attr_accessor :api_base_url

    # Network timeout (seconds) for hosted API calls. Kept short so a slow/missing
    # API never blocks a request — hosted lookups degrade to the local data.
    attr_accessor :api_timeout

    # Plate templates (Vehicles::Plates.template / .render): where fetched
    # templates are kept, and for how long. Any store with read(key) and
    # write(key, value, expires_in:) works — `Rails.cache` shares them across
    # processes. Defaults to an in-process cache. Templates are public and
    # carry nothing personal, so a long TTL is safe; the server re-renders
    # them only when VehiclesDB's plate art changes.
    attr_writer :plate_template_cache
    attr_accessor :plate_template_ttl, :image_cache_ttl, :image_miss_ttl

    def plate_template_cache
      @plate_template_cache ||= Plates::TemplateCache.new
    end

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

    # The release manifest `refresh` reads FIRST (version, schema, per-kind
    # counts, checksum when published): a few KB that decide whether the
    # 8 MB payload is worth downloading at all. Derived from `data_url`
    # (".../dist/vehicles.json" → ".../manifest.json") until you set it; set
    # nil for a self-hosted payload that has no manifest.
    attr_writer :manifest_url

    def manifest_url
      return @manifest_url unless @manifest_url == :derived

      url = data_url.to_s
      url.match?(%r{/dist/[^/]+\.json\z}) ? url.sub(%r{/dist/[^/]+\.json\z}, "/manifest.json") : nil
    end

    # Where a refreshed dataset is cached on disk. Defaults to the app's cache dir
    # (Rails) or the system temp dir — or to $VEHICLES_CACHE_DIR when set. The
    # refresh writes here; every process serves it when it is usable (see
    # Vehicles::DataSource). Several containers (web + jobs) share ONE refresh
    # by pointing this at a shared volume: `config.cache_dir = "/rails/storage/vehicles"`.
    attr_accessor :cache_path

    # Directory form of `cache_path` (the file is <dir>/vehicles.json).
    def cache_dir=(dir)
      @cache_path = File.join(dir.to_s, "vehicles.json")
    end

    def cache_dir
      File.dirname(cache_path.to_s)
    end

    # Prefer a refreshed (cached) dataset over the bundled one when present.
    # Set false to always use the bundled snapshot (fully offline/deterministic).
    attr_accessor :use_cache

    # Network timeout (seconds) for a refresh download.
    attr_accessor :refresh_timeout

    # How often (seconds) a process checks whether the dataset file changed
    # (one File.stat), so a refresh made by ANY process or container reaches
    # it without a restart. nil = never (only `Vehicles.reload!`).
    attr_accessor :reload_check_interval

    # A release is refused when any kind, or any (kind, country) slice with at
    # least 25 models, would shrink below this share of the data in use.
    # nil disables the check.
    attr_accessor :refresh_min_ratio

    # Optional last word on a release: ->(candidate, current) { … } with two
    # Vehicles::Dataset objects; falsy refuses it. Runs after every built-in
    # check, e.g. "Spain's cars must not shrink":
    #   config.refresh_guard = ->(new, old) {
    #     new.top_models(kind: :car, country: :es, limit: nil).size >=
    #       old.top_models(kind: :car, country: :es, limit: nil).size
    #   }
    attr_accessor :refresh_guard

    # --- hosted API (optional) -----------------------------------------------

    # Called with a Vehicles::HostedResult whenever a hosted call fails
    # (401/402/403/429, 5xx, timeout, network…; not for a plain "no image"
    # 404). Use it to report to your error tracker. Never allowed to raise
    # into your page: its own errors are swallowed.
    #   config.on_hosted_error = ->(r) { Rails.error.report(r.to_error, handled: true) }
    attr_accessor :on_hosted_error

    # Image payloads are cached so a page view does not pay per render: any
    # store with read(key) / write(key, value, expires_in:) (Rails.cache
    # shares it across processes). In-process by default; false disables.
    # A hit is kept `image_cache_ttl` seconds (capped by the payload's
    # `expires_at` when the API sends one), a definitive miss (404)
    # `image_miss_ttl`. Errors (401/402/429/timeouts) are never cached.
    attr_writer :image_cache

    def image_cache
      return nil if @image_cache == false

      @image_cache ||= Plates::TemplateCache.new
    end

    def initialize
      @region          = nil # no continent filter by default (global dataset)
      @api_key         = nil
      @api_base_url    = "https://vehiclesdb.com"
      @api_timeout     = 2
      @aliases         = {}
      @other_label     = "Other"
      @data_url        = "https://cdn.jsdelivr.net/gh/vehiclesdb/vehiclesdb@latest/dist/vehicles.json"
      @cache_path      = default_cache_path
      @use_cache       = true
      @refresh_timeout = 5
      @manifest_url    = :derived
      @reload_check_interval = 5
      @refresh_min_ratio = 0.9
      @refresh_guard   = nil
      @on_hosted_error = nil
      @image_cache_ttl = 86_400 # a day; variant URLs live ~30 days
      @image_miss_ttl  = 600
      @plate_template_ttl = 86_400 # a day, the server's own shared-cache lifetime
    end

    # Normalize alias keys at assignment time so lookups stay O(1) and forgiving.
    def aliases=(hash)
      @aliases = (hash || {}).each_with_object({}) do |(k, v), memo|
        memo[Vehicles.normalize(k)] = v.to_s
      end
    end

    private

    # $VEHICLES_CACHE_DIR when set (a shared volume), else tmp/cache/vehicles
    # under a Rails app, else a stable spot in the system temp
    # dir. Refreshable data, so a cache-style location is appropriate.
    def default_cache_path
      shared = ENV["VEHICLES_CACHE_DIR"].to_s
      return File.join(shared, "vehicles.json") unless shared.empty?

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
