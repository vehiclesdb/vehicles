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
end
