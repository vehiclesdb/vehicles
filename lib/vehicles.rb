# frozen_string_literal: true

require_relative "vehicles/version"
require_relative "vehicles/configuration"
require_relative "vehicles/http"
require_relative "vehicles/kind_rule"
require_relative "vehicles/make"
require_relative "vehicles/model"
require_relative "vehicles/color"
require_relative "vehicles/fuzzy"
require_relative "vehicles/model_match"
require_relative "vehicles/model_matcher"
require_relative "vehicles/text_matcher"
require_relative "vehicles/dataset_resolution"
require_relative "vehicles/dataset"
require_relative "vehicles/data_source"
require_relative "vehicles/refresh_result"
require_relative "vehicles/release_checks"
require_relative "vehicles/refresher"
require_relative "vehicles/hosted_result"
require_relative "vehicles/labels"
require_relative "vehicles/providers/local_provider"
require_relative "vehicles/providers/hosted_provider"
require_relative "vehicles/other_option"
require_relative "vehicles/id_lookup"
require_relative "vehicles/plates"
require_relative "vehicles/plates/jurisdiction"
require_relative "vehicles/plates/series"
require_relative "vehicles/plates/template_fill"
require_relative "vehicles/plates/templates"

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
      reload!
    end

    # --- data access ---------------------------------------------------------

    # Path to the bundled snapshot (or an explicit override via `data_path=`).
    def data_path
      @data_path || DATA_PATH
    end

    attr_writer :logger

    # Serve this file instead (tests, a pinned snapshot). Takes effect on the
    # next call; nil goes back to the cache/bundled rules.
    def data_path=(path)
      @data_path = path&.to_s
      reload!
    end

    # The explicit `data_path=` override, or nil.
    def data_path_override = @data_path

    # The dataset file actually in effect: an explicit override wins; otherwise
    # a refreshed cache when usable (`use_cache`, a schema this gem reads, not
    # older than the bundled data); otherwise the bundled snapshot. This is how
    # a refresh reaches the running app — no gem upgrade, no restart.
    def active_data_path = DataSource.active_path

    # The Vehicles::Dataset in effect. Every process re-checks the file every
    # `config.reload_check_interval` seconds and adopts a newer one on its own.
    def dataset = DataSource.dataset

    # Pull the latest published dataset into `config.cache_path`, so data
    # fixes and new makes land WITHOUT a gem upgrade, safely: manifest first,
    # never a downgrade, never a schema this gem cannot read, never a release
    # that lost a chunk of your data (see Vehicles::Refresher). Never raises;
    # returns a Vehicles::RefreshResult (`ok?`, `updated?`, `status`,
    # `reason`, `message`). Schedule it daily (`rails g vehicles:install`).
    #   result = Vehicles.refresh
    #   Rails.logger.warn(result.message) unless result.ok?
    def refresh = Refresher.refresh

    # `refresh.ok?` — true when the app has the latest release (just written,
    # or already current). Kept for callers of the pre-0.9.2 boolean API.
    def refresh! = Refresher.refresh!

    # Drop the in-memory dataset so the next access reloads from disk now
    # (processes also notice a changed file on their own; see `dataset`).
    def reload!
      DataSource.reset!
      Dataset.reset!
    end

    # ActiveSupport::Notifications when present ("refresh.vehicles",
    # "request.vehicles"); a no-op otherwise. Never raises.
    def instrument(name, payload)
      return unless defined?(ActiveSupport::Notifications)

      ActiveSupport::Notifications.instrument(name, payload)
    rescue StandardError
      nil
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
    #   Vehicles.makes(kind: :car, country: :es)       # makes with a car evidenced in Spain
    def makes(kind: nil, region: nil, country: nil, include_other: false)
      names = dataset.makes(kind: kind, region: region || configuration.region, country: country).map(&:name)
      append_other_name(names, include_other)
    end

    # Model display names for a make. => ["Golf", "Polo", ...]. Unknown make => [].
    #   Vehicles.models("Toyota", region: :eu, rarity: :common)
    #   Vehicles.models("Toyota", include_other: true)  # ... + the "Other" escape hatch
    # With `include_other:`, an unknown make (e.g. the "Other" make itself) yields
    # just `[other_label]`, so a make→model picker never dead-ends.
    # `fuzzy:` is forwarded to `make` (typo-tolerant by default since 0.7.8).
    #
    # With `country:` (ISO alpha-2), only models evidenced there, in that
    # country's own popularity order:
    #   Vehicles.models("SEAT", kind: :car, country: :es)  # => ["Ibiza", "Arona", "León", ...]
    # A name can repeat when the make sells it as several kinds (pass `kind:`).
    def models(make, kind: nil, body_type: nil, region: nil, rarity: nil, max_decile: nil, country: nil,
               include_other: false, fuzzy: true)
      names = make(make, fuzzy: fuzzy)&.models(kind: kind, body_type: body_type,
                                               region: region || configuration.region, country: country,
                                               rarity: rarity, max_decile: max_decile)&.map(&:name) || []
      append_other_name(names, include_other)
    end

    # The rich Make object (or nil). Forgiving: name, slug, alias — and, since
    # 0.7.8, typos: "marcedes" → Mercedes-Benz, "volkswagon" → Volkswagen
    # (bounded edit distance, only when ONE make is closest; ties → nil).
    # Pass `fuzzy: false` for exact-only resolution (the validators do).
    def make(query, fuzzy: true)
      dataset.find_make(query, fuzzy: fuzzy)
    end

    # Resolve a free-text "make + model" string into one Model (or nil).
    # Exact makes are tried first; a misspelled make is retried with the same
    # typo tolerance as `make` ("volkswagon golf"). `fuzzy: false` disables it.
    def find(query, fuzzy: true)
      dataset.find_model(query, fuzzy: fuzzy)
    end

    # Resolve a stored make + model PAIR into a Model (or nil). The structured
    # counterpart to `find` (which parses one free-text string) — reach for this
    # when your records keep make and model in separate columns and you want the
    # model's metadata (kind, body_type, …) back.
    #   Vehicles.model("Audi", "A3")   # => #<Vehicles::Model "Audi A3">
    #   Vehicles.model("vw", "golf")   # forgiving, like every other lookup
    #   Vehicles.model("Kia", "XCeed") # spacing-blind: the dataset's "X Ceed"
    #   Vehicles.model("BMW", "Serie 1")                 # => BMW 1 Series
    #   Vehicles.model("Toyota", "Land Cruiser")         # => the car (preferred)
    #   Vehicles.model("Toyota", "Land Cruiser", kind: :bus)
    #   Vehicles.model("Ford", "Focus C-Max")            # => Ford C-Max (curated form)
    #
    # Since 0.9.0, when the name itself misses, the model's published aliases
    # and curated registry spellings (Model#forms) are tried too — curated
    # data, not guessing: a spelling claimed by two different models answers
    # nil. `fuzzy:` governs the MAKE typo tolerance only, as before. Need to
    # know how a pair matched, or want cleanup/typo tolerance? `match_model`.
    #
    # Kind collisions (one nameplate as several kinds) follow the one rule
    # every VehiclesDB surface shares (Vehicles::KindRule): "Iveco Daily"
    # is the van. `kind:` picks a kind; `kinds:` allows only some (nil when
    # none of them has that name).
    def model(make_name, model_name, fuzzy: true, kind: nil, kinds: nil)
      (found = make(make_name, fuzzy: fuzzy)) &&
        ModelMatcher.exact(found, model_name, kind: KindRule.scope(kind, kinds))
    end

    # Resolve a stored make + model pair and say HOW: a Vehicles::ModelMatch
    # (model, method, confidence, via, candidates, ambiguous?), or nil when
    # nothing matched at all. The forgiving counterpart to `model` for
    # free-text data: on top of name → alias → curated form it strips an
    # echoed make name and "new" fillers ("Nuevo Citroën C3") and corrects
    # small typos ("Tuareg" → Touareg) — conservatively, and never into a
    # different number ("2008" stays a 2008). When the data knows two answers
    # the match is ambiguous (model nil, candidates set), never a pick.
    #   Vehicles.match_model("VW", "Sirocco").model     # => Volkswagen Scirocco
    #   Vehicles.match_model("Citroën", "Nuevo C4").via # => [..., "filler:nuevo", ...]
    #   Vehicles.match_model("VW", "Sirocco").rung       # => :fuzzy
    #   Vehicles.match_model("Honda", "Honda")          # => nil
    # See Vehicles::ModelMatcher for the rungs and their rules.
    #
    # Safe to write back without asking? `match.confident?` (curated rungs
    # only, never a typo guess, never ambiguous). Scope by kind with `kind:`
    # (one kind) or `kinds:` (a hard list: a record of another kind never
    # answers).
    def match_model(make_name, model_name, kind: nil, kinds: nil)
      ModelMatcher.match(make_name, model_name, kind: kind, kinds: kinds)
    end

    # Resolve ONE free-text string ("vw golf", "MERCEDES-BENZ SPRINTER",
    # "car/volkswagen/golf") the way match_model resolves a pair, and say how:
    # a Vehicles::ModelMatch, or nil. The lenient counterpart to `find`:
    # canonical id → former id → longest make prefix + the model ladder →
    # whole-text published alias (no make needed, 0.90) → cleanup → typo.
    # Nothing resolves without a make except ids and whole-text aliases.
    #   Vehicles.identify("vw tuareg").model   # => Volkswagen Touareg (:fuzzy)
    #   Vehicles.identify("golf")              # => nil
    # `kind:` scopes the name rungs (an explicit id still answers whatever
    # its kind); `kinds:` is a hard filter on every rung, ids included:
    #   Vehicles.identify("bus/iveco/daily", kinds: [:car])  # => nil
    def identify(text, kind: nil, kinds: nil) = TextMatcher.identify(text, kind: kind, kinds: kinds)

    # License plates (the bundled PRD-PLATES dataset). No argument: every
    # jurisdiction. With a code: that jurisdiction (or nil — forgiving).
    #   Vehicles.plates          # => [#<Jurisdiction nl …>, …]
    #   Vehicles.plates(:nl)     # => the Netherlands entry (33 series)
    def plates(code = nil)
      code.nil? ? Plates.jurisdictions : Plates.jurisdiction(code)
    end

    # Validate a typed registration against a jurisdiction's real series.
    # Two-tier: exact as-issued, else separator-forgiving with a formatting
    # suggestion. Never raises; unknown jurisdictions yield an empty match.
    #   Vehicles.plate("12-GB-BD", jurisdiction: :nl).valid?     # => true (exact)
    #   Vehicles.plate("1234XYZ", jurisdiction: :es).suggestion  # => "1234 XYZ"
    #   Vehicles.plate("12-AB-CD", jurisdiction: :nl).valid?     # => false (vowel purge)
    def plate(input, jurisdiction:)
      Plates.match(input, jurisdiction: jurisdiction)
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
    #   Vehicles.top_models(kind: :car, by: :mass_decile)  # by registration mass (data 2026.10.1+)
    # `limit: nil` returns every match (for a per-country picker, prefer `catalog(country:)`).
    def top_models(kind: nil, country: nil, region: nil, limit: 20, by: :global_decile)
      dataset.top_models(kind: kind, country: country, region: region, limit: limit, by: by)
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
      dataset.regions
    end

    # [[label, value], ...] of makes for a Rails `select`.
    #   Vehicles.make_options(include_other: true)  # ... + [other_label, "other"]
    def make_options(kind: nil, region: nil, country: nil, include_other: false)
      opts = dataset.makes(kind: kind, region: region || configuration.region, country: country)
                    .map { |m| [m.name, m.slug] }
      append_other_option(opts, include_other)
    end

    # [[label, value], ...] of a make's models for a Rails `select`. Unknown => [].
    #   Vehicles.model_options("audi", include_other: true)  # ... + [other_label, "other"]
    def model_options(make, kind: nil, body_type: nil, country: nil, include_other: false, fuzzy: true)
      found = make(make, fuzzy: fuzzy)
      opts = found ? found.model_options(kind: kind, body_type: body_type, country: country) : []
      append_other_option(opts, include_other)
    end

    # The "Other / not in the list" escape hatch (`other_label`, `other?`, and the
    # `include_other:` support wired into the helpers above) lives in the
    # OtherOption module, extended onto this singleton at the bottom of the file.

    # A { make => [model names] } map for the given filters — everything you need
    # to build a dependent make → model picker entirely on the client: embed it
    # once and switch the model list in a few lines of JS (or hand it to the
    # make-model-dropdown widget). No endpoint, no extra request, instant.
    # Makes are alphabetical.
    #
    # Scope it to your market with `country:` (ISO alpha-2): only models with
    # official evidence there, each make's models in that country's popularity
    # order. That is the picker list a one-country app wants — Spain's cars are
    # ~140 makes / ~1,300 models, ~14 KB of JSON — where the whole global car
    # catalog is ~330 makes / ~6,000 models (~63 KB).
    #   Vehicles.catalog(kind: :car, country: :es)  # => { "Abarth" => ["500", "595", ...], ... }
    #   Vehicles.catalog(kind: :car)                # => every car, worldwide
    # Pass `kind:` for a picker: without it a nameplate sold as a car and a
    # van appears twice.
    def catalog(kind: nil, region: nil, country: nil)
      dataset.makes(kind: kind, region: region || configuration.region, country: country).to_h do |make|
        [make.name, make.models(kind: kind, region: region || configuration.region, country: country).map(&:name)]
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
  # Canonical-id lookups (`by_id`, `successor`, `live?`) and the en/es label
  # helpers (`kind_label`, `kind_options`, `body_type_label`,
  # `body_type_options`), extended the same way.
  extend IdLookup
  extend LabelOptions
end

# Loaded after the module so its lookup tables can use Vehicles.normalize.
require_relative "vehicles/colors"

# Rails integration is opt-in and detected at load time — the gem works fine in
# plain Ruby without it.
require_relative "vehicles/railtie" if defined?(Rails::Railtie)
# If ActiveModel is already present (e.g. required directly), wire validators now.
Vehicles.load_validators! if defined?(ActiveModel::EachValidator)
