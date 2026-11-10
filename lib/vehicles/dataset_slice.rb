# frozen_string_literal: true

module Vehicles
  # `Vehicles.dataset_slice`: one scope of the dataset (Spain's cars, say) in
  # the shape of the published `dist/vehicles.json`, for clients that read
  # that file: the make-model-dropdown widget's `data` option, and the JS and
  # Python SDKs' dataset mode. Where `Vehicles.catalog` hands a page
  # `{ make => [names] }`, this hands it the records behind the names (slugs,
  # kinds, aliases, forms, former ids, availability, ranks), so the client
  # resolves stored values and produces the canonical ids
  # (`kind/make-slug/model-slug`) the way it would on the full release.
  #
  # Lean on purpose. Each model keeps what resolution, ordering and scoping
  # read: name, slug, kind, aliases, forms, former_ids, availability,
  # global_decile, mass_decile, country_ranks and registration_years. It drops
  # `regions` (a rollup of availability) and `body_type`. With `country:`,
  # `availability` and `country_ranks` keep only that country: every record
  # in the slice is evidenced there, and the other countries' entries are
  # most of the weight. Spain's cars (data 2026.11.3): ~360 KB of JSON, ~57 KB gzipped.
  module DatasetSlice
    # Model keys copied as published, in dist order. The two per-country keys
    # are projected separately.
    MODEL_KEYS = %w[name slug kind aliases forms former_ids global_decile mass_decile].freeze

    module_function

    def build(dataset, kind: nil, kinds: nil, region: nil, country: nil)
      scope = KindRule.scope(kind, kinds)
      code = country&.to_s&.downcase
      makes = dataset.makes(kind: kind, region: region).filter_map do |make|
        models = make.models(region: region).select do |m|
          KindRule.allows?(scope, m) && (code.nil? || m.available_in?(code))
        end
        make_record(make, models, code) unless models.empty?
      end
      header(dataset, makes.flat_map { |m| m["kinds"] }.uniq.sort).merge("makes" => makes)
    end

    def header(dataset, kinds)
      { "version" => dataset.version, "schema_version" => dataset.schema_version,
        "kinds" => kinds, "license" => dataset.license,
        "attribution" => dataset.attribution }.compact
    end

    def make_record(make, models, code)
      record = { "name" => make.name, "slug" => make.slug,
                 "kinds" => models.map { |m| m.kind.to_s }.uniq.sort }
      record["aliases"] = make.aliases unless make.aliases.empty?
      record["former_slugs"] = make.former_slugs unless make.former_slugs.empty?
      record.merge("models" => models.map { |m| model_record(m, code) })
    end

    def model_record(model, code)
      record = MODEL_KEYS.each_with_object({}) do |key, out|
        value = case key
                when "slug" then model.model_slug
                when "kind" then model.kind.to_s
                else model.public_send(key)
                end
        out[key] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
      record["availability"] = code ? [code] : model.availability
      ranks = code ? model.country_ranks.slice(code) : model.country_ranks
      record["country_ranks"] = ranks unless ranks.empty?
      years = model.registration_years
      record["registration_years"] = { "first" => years[:first], "last" => years[:last] } if years
      record
    end
  end

  # Extended onto Vehicles (see the bottom of lib/vehicles.rb).
  module DatasetSliceExport
    # The same scope as `catalog`, as records in the shape of the published
    # `dist/vehicles.json` (a Hash, ready for `to_json`): what the
    # make-model-dropdown widget's `data` option and the JS/Python SDKs'
    # dataset mode read. Embed it in the page and the widget resolves stored
    # values and canonical ids with no request to a CDN or the API.
    #   Vehicles.dataset_slice(kind: :car, country: :es)
    #   # => { "version" => "2026.11.3", "schema_version" => 2, "kinds" => ["car"],
    #   #      "license" => "CC-BY-4.0", "attribution" => {...},
    #   #      "makes" => [{ "name" => "SEAT", "slug" => "seat", "kinds" => ["car"],
    #   #                    "models" => [{ "name" => "Ibiza", "slug" => "ibiza", "kind" => "car", ... }] }] }
    # With `country:`, each record's `availability` and `country_ranks` keep
    # only that country (Spain's cars: ~360 KB of JSON, ~57 KB gzipped).
    # `regions` and `body_type` are left out. See Vehicles::DatasetSlice.
    def dataset_slice(kind: nil, region: nil, country: nil, kinds: nil)
      DatasetSlice.build(dataset, kind: kind, kinds: kinds, region: region || configuration.region, country: country)
    end
  end
end
