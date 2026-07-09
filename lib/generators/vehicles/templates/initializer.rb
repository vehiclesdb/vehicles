# frozen_string_literal: true

# vehicles configuration.
#
# Everything here is OPTIONAL — the gem ships sensible defaults and a bundled
# dataset, so it works with zero configuration. Uncomment what you need.

Vehicles.configure do |config|
  # Default region for queries. Today the bundled data covers the EU market;
  # :us / :gb / :au / :nz / :ca packs are on the roadmap (the API is already
  # region-aware, so adding them won't change your code).
  # config.region = :eu

  # Optional: a VehiclesDB API key unlocks hosted enrichment — production years,
  # model images (year- and color-accurate), and market segments — on the same
  # Vehicles::Model objects you already use. Without a key, everything still
  # works on the bundled data; those richer fields just return nil.
  # config.api_key = ENV["VEHICLESDB_API_KEY"]

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
  # makes WITHOUT upgrading the gem, schedule VehiclesRefreshJob (see app/jobs)
  # — it pulls the latest published dataset into a local cache, which loads
  # prefer over the bundled copy. Defaults below are sensible; override if needed.
  #
  # config.data_url   = "https://cdn.jsdelivr.net/gh/vehiclesdb/vehiclesdb@latest/dist/vehicles.json"
  # config.cache_path = Rails.root.join("tmp", "cache", "vehicles", "vehicles.json")
  # config.use_cache  = true   # set false to always use the bundled snapshot (fully offline/deterministic)
end
