# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `Make#models` / `Dataset#all_models` now return **frozen** arrays — accidental
  caller mutation no longer corrupts the shared, memoized dataset process-wide.
- `normalize`/`slugify` (and every lookup built on them) no longer raise on
  invalid-encoding/binary input — garbage in yields empty/nil, per the contract.
- `Make#model` is now exact-match only; partial input like `model("a")` returns
  `nil` instead of falsely resolving to "A3" (the `vehicle_model` validator relies
  on this). Fuzzy/partial matching remains in `Vehicles.search`.
- `reset_configuration!` now also clears `@data_path` and the `Dataset` cache, so
  it truly returns the gem to a pristine state (test-safe).
- README/docstring accuracy: real first make is "Alfa Romeo" (not "Abarth"),
  `data_version` is `2026.06.0`, dropped the non-existent `:crossover` body type,
  and the Appraisal example is `rails-8.0`.

### Added
- `Vehicles.catalog(kind:, region:)` — a `{ make => [model names] }` map, so a
  dependent make→model picker can be built fully client-side (embed once, no
  route/controller/fetch). Now the recommended dropdown recipe in the README.
- `Vehicles.model(make, model)` — structured make+model pair lookup.
- Canonical color palette: `Vehicles.colors`, `Vehicles.color(query)` (forgiving,
  with synonyms), `Vehicles.color_options`, and the `Vehicles::Color` value object
  (slug/name/hex) — shared vocabulary for color dropdowns and future image variants.
- README "Recommended integration" + reference schema (store identity; derive the
  rest) and a "Colors" section.

## [0.1.0] - 2026-06-23

Initial release.

### Added
- Bundled, zero-config dataset of **EU car make/model nameplates** (~47 makes,
  ~456 models, dataset version `2026.06.0`), derived from RDW Open Data (CC-BY 4.0).
- Each model carries a `kind` (`:car` today) and a curated `body_type`
  (`:hatchback`, `:sedan`, `:suv`, `:mpv`, `:coupe`, `:wagon`, `:convertible`,
  `:roadster`, `:van`).
- Core query API: `Vehicles.makes`, `Vehicles.models`, `Vehicles.make`,
  `Vehicles.find`, `Vehicles.search`, with `kind:` / `body_type:` / `region:` filters.
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
