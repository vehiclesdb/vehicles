# frozen_string_literal: true

require_relative "vehicles/version"
require_relative "vehicles/configuration"
require_relative "vehicles/make"
require_relative "vehicles/model"
require_relative "vehicles/color"
require_relative "vehicles/dataset"
require_relative "vehicles/providers/local_provider"
require_relative "vehicles/providers/hosted_provider"

# Car makes & models for your Rails app — dropdowns, search, validation. Bundled
# data, zero config, no network calls. Standalone first; an SDK for the hosted
# VehiclesDB API second.
#
#   Vehicles.makes                   # => ["Abarth", "Alfa Romeo", "Audi", ...]
#   Vehicles.models("VW")            # => ["Golf", "Polo", "Tiguan", ...]
#   Vehicles.find("vw golf")         # => #<Vehicles::Model "Volkswagen Golf">
#   Vehicles.make_options            # => [["Abarth", "abarth"], ...]  (for select)
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

    # Reset config + caches. Primarily for the test suite.
    def reset_configuration!
      @configuration = Configuration.new
      @providers = nil
      Providers::HostedProvider.reset!
    end

    # --- data access ---------------------------------------------------------

    def data_path
      @data_path || DATA_PATH
    end

    attr_writer :data_path, :logger

    def dataset
      Dataset.load(data_path)
    end

    # Snapshot version the gem ships, e.g. "2026.06.0".
    def data_version
      dataset.version
    end

    # Region the bundled data covers, as a Symbol, e.g. :eu.
    def region
      dataset.region.to_s.downcase.to_sym
    end

    # --- core query API ------------------------------------------------------

    # Make display names. => ["Abarth", "Alfa Romeo", ...]
    def makes(kind: nil, region: nil)
      dataset.makes(kind: kind, region: region || configuration.region).map(&:name)
    end

    # Model display names for a make. => ["Golf", "Polo", ...]. Unknown make => [].
    def models(make, kind: nil, body_type: nil, region: nil)
      return [] if (region || configuration.region) && !dataset.region?(region || configuration.region)

      found = make(make)
      found ? found.models(kind: kind, body_type: body_type).map(&:name) : []
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
    def make_options(kind: nil, region: nil)
      dataset.makes(kind: kind, region: region || configuration.region).map { |m| [m.name, m.slug] }
    end

    # [[label, value], ...] of a make's models for a Rails `select`. Unknown => [].
    def model_options(make, kind: nil, body_type: nil)
      found = make(make)
      found ? found.model_options(kind: kind, body_type: body_type) : []
    end

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
    # "Škoda" => "skoda". Used everywhere lookups need to be forgiving.
    #
    # NFKD splits "š" into "s" + a combining caron; we strip the combining marks
    # (\p{Mn}) BEFORE the separator gsub, or "Škoda" would normalize to "s koda".
    def normalize(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}+/, "").downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    # Slugify a display name: "Alfa Romeo" => "alfa-romeo", "Škoda" => "skoda".
    def slugify(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}+/, "").downcase
         .gsub(/[^a-z0-9]+/, "-").gsub(/(\A-|-\z)/, "")
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
end

# Loaded after the module so its lookup tables can use Vehicles.normalize.
require_relative "vehicles/colors"

# Rails integration is opt-in and detected at load time — the gem works fine in
# plain Ruby without it.
require_relative "vehicles/railtie" if defined?(Rails::Railtie)
# If ActiveModel is already present (e.g. required directly), wire validators now.
Vehicles.load_validators! if defined?(ActiveModel::EachValidator)
