# frozen_string_literal: true

# vehicles configuration.
#
# Everything here is OPTIONAL — the gem ships sensible defaults and a bundled
# dataset, so it works with zero configuration. Uncomment what you need.

Vehicles.configure do |config|
  # Optional default CONTINENT filter (:eu/:na/:as/:sa/:oc/:af). The bundled
  # data is global; nil (the default) means every market. For one COUNTRY,
  # pass `country:` where you build pickers: Vehicles.catalog(kind: :car, country: :es).
  # config.region = :eu

  # Optional: a VehiclesDB API key unlocks studio model images
  # (`model.image(color: "red")`) on the same Vehicles::Model objects you already
  # use. Without a key, everything still works on the bundled data; images are nil.
  # config.api_key = ENV["VEHICLESDB_API_KEY"]
  #
  # Image payloads are cached (in-process by default); share them across
  # processes with Rails.cache. Hosted failures (bad key, out of credits, rate
  # limited, timeouts) are never raised: report them here.
  # config.image_cache = Rails.cache
  # config.on_hosted_error = ->(result) { Rails.error.report(result.to_error, handled: true) }

  # Optional: your own make aliases, merged over the built-ins. Matched
  # forgivingly (case/diacritics-insensitive).
  # config.aliases = { "Chevy" => "Chevrolet", "Landy" => "Land Rover" }

  # Optional: label for the "Other / not in the list" escape-hatch option (for
  # make/model pickers). Defaults to "Other"; set it to your UI language. Turn it
  # on per field with `Vehicles.makes(include_other: true)` /
  # `Vehicles.make_options(include_other: true)` and accept it in validation with
  # `validates :make, vehicle_make: { allow_other: true }`.
  # config.other_label = "Other"

  # --- Data refresh (optional) ----------------------------------------------
  # The gem works offline with its bundled snapshot. To get data fixes and new
  # makes WITHOUT upgrading the gem, schedule VehiclesRefreshJob (see app/jobs).
  # It writes a checked release to `cache_path`; every process serves it once
  # it is newer than the bundled data, re-checking the file every few seconds.
  #
  # Web and jobs in separate containers (Kamal, Docker)? Point both at ONE
  # shared volume so a refresh run by the job container reaches the web one:
  # config.cache_dir = Rails.root.join("storage", "vehicles")  # or ENV VEHICLES_CACHE_DIR
  #
  # config.use_cache  = true   # set false to always use the bundled snapshot (fully offline/deterministic)
  # config.refresh_min_ratio = 0.9  # refuse a release that shrinks a kind or a country below 90%
  # config.refresh_guard = ->(new_data, current) { true } # your own last check (Vehicles::Dataset objects)
end
