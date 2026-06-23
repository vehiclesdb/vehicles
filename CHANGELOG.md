# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
