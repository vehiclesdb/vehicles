# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.2] - 2026-08-02

### Fixed

- `Plates::Series#format_serial` reconstructed variable-length serials by
  walking the fixed display pattern, misplacing separators ("M1234LA" came
  back as "M1-234L-A" instead of "M-1234-LA"). The pattern walk now applies
  only when the serial exactly fills the pattern; length-mismatched serials
  reconstruct from the regex segmented at its separators (new
  `Series.segment_separators`, riding the dataset separator contract), and
  a serial neither path can place comes back untouched rather than
  mis-punctuated.

### Changed

- `Plates::Series#period_label` no longer presents instrument-dated starts
  as the series era: rows whose `period_evidence` is `instrument-in-force`
  or `instrument-window` label as "≤1999–2000" ("began by", not "began
  in"). New `Series#period_evidence`, `#issued_regexp`,
  `#issued_separators` readers for consumers mirroring the reconstruction.

## [0.6.1] - 2026-08-01

### Added

- `Model#former_ids` — the full canonical ids a record absorbed through the
  dataset's append-only migration contract (e.g. `car/alfa-romeo/159sw`).
  The field was already in the bundled snapshot; the reader now surfaces it,
  so integrators can migrate stored ids without re-parsing the raw JSON.
  Also included in `Model#to_h`.

## [0.6.0] - 2026-07-27

License plates become a first-class citizen: the PRD-PLATES registration-mark
dataset ships in the gem, bundled and offline like everything else.

### Added
- `Vehicles.plate(input, jurisdiction:)` — two-tier plate validation:
  exact as-issued, then separator-forgiving ("1234XYZ" == "1234 XYZ" ==
  "1234-xyz") with `Match#suggestion` returning the as-issued formatting.
  Leniency forgives punctuation, never the alphabet — strict regexes encode
  what each authority really issues. `Match#strict?` separates
  authority-alphabet hits from recall-only catch-alls (export plates etc.).
- `Vehicles.plates` / `Vehicles.plates(:nl)` — the full series data:
  73 series across NL/ES/DE/US-FL (gate L0, NL corpus-proven), each with
  pattern, period, class, categories, sourced design facts and citations.
- Bundled data under `data/plates/` (CC-BY, pinned upstream commit in
  `data/plates/PROVENANCE.md`).

The hosted images API is **live** — this release points the wired-up provider
seam at the real thing.

### Added
- `Model#image(color:, size:)` returns a rendered variant URL from the live
  VehiclesDB images API (`:sm` 320×180, `:md` 640×360, `:lg` 1280×720, webp).
  Mint a key at <https://vehiclesdb.com/settings/api-keys> and set
  `config.api_key`; without a key it stays nil, as always.
- `Model#images(color:)` returns the full payload: every variant with
  dimensions, the rendered palette for the model, served-vs-requested color
  (un-rendered colors fall back honestly instead of 404ing), provenance.

### Changed
- `config.api_base_url` default is now `https://vehiclesdb.com` (the live API
  origin; endpoint paths carry `/v1`). It must be an ORIGIN — no path suffix.
- `Model#image` accepts `year:` but does not send it: `year`/`trim` are
  reserved filters server-side (the API 422s on them by contract) until
  year-accurate renders ship.

## [0.4.1] - 2026-07-26

Data-only refresh to VehiclesDB dataset **2026.07.4** — the July correction
pass: 16,948 models across 858 makes (~1,200 registry-junk and duplicate
records removed, per-marque naming canon applied). No API changes.

## [0.4.0] - 2026-07-09

A first-class **"Other / not in the list" escape hatch** for make/model pickers,
so a vehicle the dataset doesn't cover is never a dead end:

- `include_other:` on `makes`, `models`, `make_options`, and `model_options`
  appends the option (name lists get the label; option pairs get the stable
  `"other"` slug). Idempotent.
- `allow_other: true` on the `vehicle_make` / `vehicle_model` validators accepts
  it, so the dropdown and the validation agree by construction.
- `config.other_label` (default `"Other"`) localizes the label; `Vehicles.other?`
  recognizes the label or the canonical `"other"` slug (case/diacritics-forgiving),
  and `Vehicles.other_label` reads it back.

## [0.3.0] - 2026-07-05

Continent filtering, rarity tiers, and alternate names — plus a cleaner
dataset (Tesla is now 6 nameplates, not 43; ~470 duplicate makes/models
merged).

### Added
- **Continents**: `model.regions` (`[:eu, :as, …]`), `model.available_in_region?(:eu)`,
  and predicate sugar `.european?`/`.asian?`/`.north_american?`/`.south_american?`/
  `.oceanian?`/`.african?`. `region:` on `makes`/`models`/`top_models` now
  filters by continent; `Vehicles.regions` lists covered continents;
  `make.continents` / `make.in_region?`.
- **Rarity tiers**: `model.rarity` → `:common` (decile 1–3) / `:average` (4–7) /
  `:rare` (8–10) / `:unknown` (unranked); `model.common?` / `model.rare?`.
  Filter with `Vehicles.catalog_slice(kind:, region:, rarity:, max_decile:)`
  and `Vehicles.models(make, rarity:, max_decile:)` — the "how much data do I
  want to show" knob, without exposing raw counts.
- **Alternate names**: `make.aliases` / `model.aliases` now carry documented
  nicknames, initialisms and native-script names (Chevy, VW, 比亚迪, カローラ,
  Rabbit, Pajero/Montero/Shogun…). All resolve in lookups — `Vehicles.make("比亚迪")`
  and `Vehicles.make("Chevy")` both find the make.
- `model.to_h` gains `regions`, `rarity`, `aliases`.

### Changed
- `config.region` now defaults to **nil** (no continent filter — the whole
  global dataset) instead of `:eu`. `region:` means a continent everywhere; a
  country code like `:us` returns nothing (use `country:` on `top_models` for
  countries). Bundled snapshot: VehiclesDB `2026.07.2`.

## [0.2.0] - 2026-07-05

The global multi-kind release: the bundled dataset grows from ~456 EU car
models to **18,556 models across 928 makes and six kinds** (cars,
motorcycles, mopeds, vans, trucks, buses), reconciled from official registers
of 14 countries — see [VehiclesDB](https://github.com/vehiclesdb/vehiclesdb).

### Added
- **Popularity**: `model.global_decile` (1 = top 10% worldwide, measured from
  official registration counts; `nil` = unranked) and `model.popular?`
  (decile ≤ 2, honest `false` when unranked).
- **Availability**: `model.availability` (ISO alpha-2 country codes with
  official evidence) and `model.available_in?(:nl)`. Evidence of presence,
  not marketing history — grey imports count.
- `Vehicles.top_models(kind:, country:, limit:)` — ranked by popularity,
  perfect for "common choices" pickers. Unranked models never outrank ranked.
- `Vehicles.kinds` and `model.two_wheeler?` (motorcycle OR moped — the union
  two-wheeler pickers want).
- **`vehicles-mcp`** — a bundled, read-only MCP server over the dataset
  (stdio, zero config, stdlib-only): `search_makes`, `search_models`,
  `get_model`, `top_models`. Wire it into any MCP host with
  `{ "command": "vehicles-mcp" }`.
- `model.to_h` now includes `global_decile` and `availability`.

### Changed
- **Dataset**: bundled snapshot is now VehiclesDB `2026.07.0` (global,
  6 kinds, popularity + availability). `Vehicles.region` returns `:global`;
  the region gate treats a global snapshot as covering every region, so
  `region: :eu` callers keep working unchanged.
- `model.body_type` is `nil` for kinds without an honest body vocabulary
  (a truck is not a "hatchback"); predicates return `false` on `nil`.
  Cars keep their curated body types, unchanged.
- Removed the built-in `"vauxhall" → Opel` lookup alias: the dataset now
  ships Vauxhall and Opel as separate makes (deliberately — separate GB/EU
  model names), and the alias would have shadowed the real Vauxhall records.

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

[Unreleased]: https://github.com/vehiclesdb/vehicles/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/vehiclesdb/vehicles/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/vehiclesdb/vehicles/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/vehiclesdb/vehicles/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/vehiclesdb/vehicles/compare/v0.1.1...v0.2.0
[0.1.0]: https://github.com/vehiclesdb/vehicles/releases/tag/v0.1.0
