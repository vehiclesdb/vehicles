# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-06-23

### Fixed
- **Data refresh** now handles real HTTP responses correctly. `Net::HTTP` returns
  an ASCII-8BIT body (e.g. gzip-decompressed); with multibyte UTF-8 data and
  `Encoding.default_internal = UTF-8` (as Rails sets), the cache write raised
  `Encoding::UndefinedConversionError` and the refresh silently failed (falling
  back to the bundled snapshot). The fetched body is now tagged UTF-8 and the
  cache is written with `File.binwrite` (no transcoding). `Vehicles.refresh!`
  works under Rails.

## [0.1.0] - 2026-06-23

Initial release.

### Added
- Bundled, zero-config dataset of **EU car make/model nameplates** (~47 makes,
  ~456 models, dataset version `2026.06.0`), derived from RDW Open Data (CC-BY 4.0).
- Each model carries a `kind` (`:car` today) and a curated `body_type`
  (`:hatchback`, `:sedan`, `:suv`, `:mpv`, `:coupe`, `:wagon`, `:convertible`,
  `:roadster`, `:van`).
- Core query API: `Vehicles.makes`, `Vehicles.models`, `Vehicles.make`,
  `Vehicles.find`, `Vehicles.model(make, model)`, `Vehicles.search`, with
  `kind:` / `body_type:` / `region:` filters.
- `Vehicles.catalog(kind:, region:)` — a `{ make => [model names] }` map, so a
  dependent make→model picker can be built fully client-side (embed once, no
  route/controller/fetch). The recommended dropdown recipe in the README.
- **Data refresh** (optional): `Vehicles.refresh!` pulls the latest published
  dataset (from the VehiclesDB data repo via CDN) into a local file cache; loads
  prefer the cache over the bundled snapshot, so data fixes reach an app **without
  a gem upgrade**. Bundled data remains the offline, zero-config floor. Config:
  `data_url` / `cache_path` / `use_cache`. The install generator drops a
  schedulable `VehiclesRefreshJob`. Error-isolated (never raises; a bad download
  never clobbers good data).
- Canonical color palette: `Vehicles.colors`, `Vehicles.color(query)` (forgiving,
  with synonyms), `Vehicles.color_options`, and the `Vehicles::Color` value object
  (slug/name/hex) — shared vocabulary for color dropdowns and future image variants.
- Rails dropdown helpers: `Vehicles.make_options`, `Vehicles.model_options`.
- Forgiving lookups: case-, diacritic-, slug-, and alias-insensitive
  (`"VW"`, `"merc"`, `"Vauxhall"`, `"Škoda"` all resolve).
- `Vehicles::Make` and `Vehicles::Model` value objects with predicate sugar
  (`car.suv?`, `car.hatchback?`) and `to_h`.
- Drop-in ActiveModel validators: `vehicle_make` and `vehicle_model`.
- Provider seam (`LocalProvider` + `HostedProvider`) for optional hosted
  VehiclesDB enrichment (`model.years` / `#segment` / `#image`), gated on an
  API key and degrading gracefully to local data.
- Install generator that writes a configuration initializer (no migration —
  the gem has no database table).

[Unreleased]: https://github.com/rameerez/vehicles/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rameerez/vehicles/releases/tag/v0.1.0
