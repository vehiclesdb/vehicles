# frozen_string_literal: true

require_relative "vehicles/version"
require_relative "vehicles/configuration"
require_relative "vehicles/make"
require_relative "vehicles/model"
require_relative "vehicles/color"
require_relative "vehicles/dataset"
require_relative "vehicles/refresher"
require_relative "vehicles/providers/local_provider"
require_relative "vehicles/providers/hosted_provider"
require_relative "vehicles/other_option"

# Car makes & models for your Rails app — dropdowns, search, validation. Bundled
# data, zero config, no network calls. Standalone first; an SDK for the hosted
# VehiclesDB API second.
#
#   Vehicles.makes                   # => ["Alfa Romeo", "Audi", "BMW", ...]
#   Vehicles.models("VW")            # => ["Golf", "Polo", "Tiguan", ...]
#   Vehicles.find("vw golf")         # => #<Vehicles::Model "Volkswagen Golf">
#   Vehicles.make_options            # => [["Alfa Romeo", "alfa-romeo"], ...]  (for select)
module Vehicles
  class Error < StandardError; end

  # The bundled snapshot, packaged in the gem. Overridable via `Vehicles.data_path=`.
  DATA_PATH = File.expand_path("../data/vehicles.json", __dir__)

  class << self
    # --- configuration -------------------------------------------------------

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Reset config + caches (config, data path, dataset, providers). Primarily
    # for the test suite — genuinely returns the gem to a pristine state.
    def reset_configuration!
      @configuration = Configuration.new
      @providers = nil
      @data_path = nil
      Dataset.reset!
      Providers::HostedProvider.reset!
    end

    # --- data access ---------------------------------------------------------

    # Path to the bundled snapshot (or an explicit override via `data_path=`).
    def data_path
      @data_path || DATA_PATH
    end

    attr_writer :data_path, :logger

    # The dataset file actually in effect: an explicit override wins; otherwise a
    # refreshed cache (if present and `use_cache`); otherwise the bundled snapshot.
    # This is how a refresh reaches the running app — no gem upgrade needed.
    def active_data_path
      return @data_path if @data_path
      return Refresher.cached_path if configuration.use_cache && Refresher.cached?

      DATA_PATH
    end

    def dataset
      Dataset.load(active_data_path)
    end

    # Pull the latest published dataset into the local cache, so data fixes / new
    # makes land WITHOUT a gem upgrade. Returns true/false; never raises. Schedule
    # it (e.g. a daily job — `rails g vehicles:install` sets one up).
    def refresh!
      Refresher.refresh!
    end

    # Drop the in-memory dataset so the next access reloads from disk (after a
    # refresh, a cache clear, or a `data_path=` change).
    def reload!
      Dataset.reset!
    end

    # Version of the dataset currently in effect (refreshed cache or bundled),
    # e.g. "2026.06.0".
    def data_version
      dataset.version
    end

    # Region the bundled data covers, as a Symbol, e.g. :eu.
    def region
      dataset.region.to_s.downcase.to_sym
    end

    # --- core query API ------------------------------------------------------

    # Make display names. => ["Abarth", "Alfa Romeo", ...]
    #   Vehicles.makes(kind: :motorcycle, region: :as)  # continent filter
    #   Vehicles.makes(include_other: true)             # ... + the "Other" escape hatch
    def makes(kind: nil, region: nil, include_other: false)
      names = dataset.makes(kind: kind, region: region || configuration.region).map(&:name)
      append_other_name(names, include_other)
    end

    # Model display names for a make. => ["Golf", "Polo", ...]. Unknown make => [].
    #   Vehicles.models("Toyota", region: :eu, rarity: :common)
    #   Vehicles.models("Toyota", include_other: true)  # ... + the "Other" escape hatch
    # With `include_other:`, an unknown make (e.g. the "Other" make itself) yields
    # just `[other_label]`, so a make→model picker never dead-ends.
    def models(make, kind: nil, body_type: nil, region: nil, rarity: nil, max_decile: nil, include_other: false)
      names = make(make)&.models(kind: kind, body_type: body_type, region: region || configuration.region,
                                 rarity: rarity, max_decile: max_decile)&.map(&:name) || []
      append_other_name(names, include_other)
    end

    # The rich Make object (or nil). Forgiving: name, slug, or alias.
    def make(query)
      dataset.find_make(query)
    end

    # Resolve a free-text "make + model" string into one Model (or nil).
    def find(query)
      dataset.find_model(query)
    end

    # Resolve a stored make + model PAIR into a Model (or nil). The structured
    # counterpart to `find` (which parses one free-text string) — reach for this
    # when your records keep make and model in separate columns and you want the
    # model's metadata (kind, body_type, …) back.
    #   Vehicles.model("Audi", "A3")   # => #<Vehicles::Model "Audi A3">
    #   Vehicles.model("vw", "golf")   # forgiving, like every other lookup
    def model(make_name, model_name)
      found = make(make_name)
      found&.model(model_name)
    end

    # Every model matching a query, ranked. => [Vehicles::Model, ...]
    def search(query)
      dataset.search(query)
    end

    # Every kind in the dataset. => [:bus, :car, :moped, :motorcycle, :truck, :van]
    def kinds
      dataset.kinds
    end

    # The most popular models by official registration counts, most popular
    # first. Filter by country (ISO alpha-2) or continent (:eu/:as/…).
    #   Vehicles.top_models(kind: :car, country: :nl, limit: 10).map(&:name)
    #   Vehicles.top_models(kind: :motorcycle, region: :as, limit: 10)
    def top_models(kind: nil, country: nil, region: nil, limit: 20)
      dataset.top_models(kind: kind, country: country, region: region, limit: limit)
    end

    # A curated slice of models by kind/continent/rarity — the "give me sensible
    # data to show" entry point (ranked, unranked models excluded when a rarity
    # or max_decile filter is set).
    #   Vehicles.catalog_slice(kind: :car, region: :eu, rarity: :common)
    def catalog_slice(kind: nil, region: nil, rarity: nil, max_decile: nil)
      dataset.all_models_filtered(kind: kind, region: region || configuration.region,
                                  rarity: rarity, max_decile: max_decile)
    end

    # Continent codes present in the dataset. => [:af, :as, :eu, :na, :oc, :sa]
    def regions
      @regions ||= dataset.all_models.flat_map(&:regions).uniq.sort
    end

    # --- colors (canonical reference palette) --------------------------------

    # The canonical color palette, frequency-ordered. => [Vehicles::Color, ...]
    def colors
      Colors::ALL
    end

    # [[name, slug], ...] for a Rails `select`. Names are English — localize the
    # labels in your app; the slug is the stable value you store.
    def color_options
      Colors::ALL.map { |c| [c.name, c.slug] }
    end

    # Resolve a color by slug or name (forgiving: case, diacritics, synonyms like
    # "gray"→grey, "navy"→blue). Returns a Vehicles::Color, or nil.
    def color(query)
      q = normalize(query)
      return nil if q.empty?

      Colors::BY_SLUG[q] || Colors::BY_NAME[q] || Colors::BY_SLUG[Colors::SYNONYMS[q]]
    end

    # [[label, value], ...] of makes for a Rails `select`.
    #   Vehicles.make_options(include_other: true)  # ... + [other_label, "other"]
    def make_options(kind: nil, region: nil, include_other: false)
      opts = dataset.makes(kind: kind, region: region || configuration.region).map { |m| [m.name, m.slug] }
      append_other_option(opts, include_other)
    end

    # [[label, value], ...] of a make's models for a Rails `select`. Unknown => [].
    #   Vehicles.model_options("audi", include_other: true)  # ... + [other_label, "other"]
    def model_options(make, kind: nil, body_type: nil, include_other: false)
      found = make(make)
      opts = found ? found.model_options(kind: kind, body_type: body_type) : []
      append_other_option(opts, include_other)
    end

    # The "Other / not in the list" escape hatch (`other_label`, `other?`, and the
    # `include_other:` support wired into the helpers above) lives in the
    # OtherOption module, extended onto this singleton at the bottom of the file.

    # A { make => [model names] } map for the given filters — everything you need
    # to build a dependent make → model picker entirely on the client: embed it
    # once (`Vehicles.catalog(kind: :car).to_json`) and switch the model list in a
    # few lines of JS. No endpoint, no extra request, instant. The whole car
    # catalog is small (tens of KB), so this is the simplest path for most apps.
    #   Vehicles.catalog(kind: :car)   # => { "Audi" => ["A3", "A4", ...], ... }
    def catalog(kind: nil, region: nil)
      makes(kind: kind, region: region).to_h do |name|
        [name, models(name, kind: kind, region: region)]
      end
    end

    # --- provider resolution (hosted enrichment, optional) -------------------

    # Ask each available provider for an attribute, hosted first, until one gives
    # a non-nil answer. Returns nil if none can. Never raises. Backs Model#years
    # / #segment / #image.
    def resolve(attribute, model, **opts)
      providers.each do |provider|
        next unless provider.available?

        value = provider.public_send(attribute, model, **opts)
        return value unless value.nil?
      rescue StandardError => e
        # A misbehaving provider must never break a model read — log and move on.
        logger&.error("[vehicles] provider #{provider} failed on #{attribute}: #{e.message}")
        next
      end
      nil
    end

    def providers
      @providers ||= [Providers::HostedProvider, Providers::LocalProvider]
    end

    # --- helpers -------------------------------------------------------------

    # Match-normalize a string: fold diacritics, downcase, collapse anything
    # non-alphanumeric to single spaces. "Mercedes-Benz" => "mercedes benz",
    # "Škoda" => "skoda". Used everywhere lookups need to be forgiving — so it must
    # NEVER raise (the API contract is "garbage in => empty/nil out, not an error").
    def normalize(str)
      fold_diacritics(str).downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    # Slugify a display name: "Alfa Romeo" => "alfa-romeo", "Škoda" => "skoda".
    def slugify(str)
      fold_diacritics(str).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/(\A-|-\z)/, "")
    end

    # Shared diacritic folding for normalize/slugify. NFKD splits "š" into "s" + a
    # combining caron; we strip the combining marks (\p{Mn}) BEFORE the separator
    # gsub, or "Škoda" would become "s koda". Defends against non-UTF-8/invalid
    # encodings (e.g. a binary string) so callers never hit Encoding errors.
    def fold_diacritics(str)
      s = str.to_s
      s = s.dup.force_encoding(Encoding::UTF_8) unless s.encoding == Encoding::UTF_8
      s = s.scrub("") unless s.valid_encoding?
      s.unicode_normalize(:nfkd).gsub(/\p{Mn}+/, "")
    end

    def logger
      @logger ||= (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil)
    end

    # Require the ActiveModel validators (idempotent; no-op without ActiveModel).
    def load_validators!
      return if @validators_loaded
      return unless defined?(ActiveModel::EachValidator)

      require_relative "vehicles/validators/vehicle_make_validator"
      require_relative "vehicles/validators/vehicle_model_validator"
      @validators_loaded = true
    end
  end

  # The "Other" escape hatch: `other_label` / `other?` (public) and the private
  # `append_other_*` builders the `include_other:` helpers call. Extended here so
  # they become Vehicles singleton methods with access to `configuration` /
  # `normalize`.
  extend OtherOption
end

# Loaded after the module so its lookup tables can use Vehicles.normalize.
require_relative "vehicles/colors"

# Rails integration is opt-in and detected at load time — the gem works fine in
# plain Ruby without it.
require_relative "vehicles/railtie" if defined?(Rails::Railtie)
# If ActiveModel is already present (e.g. required directly), wire validators now.
Vehicles.load_validators! if defined?(ActiveModel::EachValidator)
