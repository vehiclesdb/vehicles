# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.2] - 2026-11-10

Everything below the plates fixes comes from dogfooding the gem in a production Rails app (CarHey) and making each workaround it had to write a general feature.

### Changed (behaviour)
- **One kind-collision rule, shared by every VehiclesDB surface** (`Vehicles::KindRule`; vehiclesdb RESOLUTION.md §3). When one nameplate is several records (Iveco "Daily" is a van, a truck and a bus) and no kind is given, `Vehicles.model`, `Make#model`, `match_model` and `identify` pick the lowest `mass_decile`, then van → car → bus → truck → moped → motorcycle, then the id. Until 0.9.1 the gem preferred the car (else file order) while the SDKs used another tie-break, so the stored id depended on the door a user came through. Backtested on register counts, the rule picks the most-registered kind in 87% of collision groups (car-first: 43%). Pass `kind:` to keep a kind.
- **`Model#==`, `eql?` and `hash` compare the canonical id**, not the composite slug: the car and the van of one nameplate are no longer equal (they used to collapse in sets, `uniq` and hash keys).
- `Vehicles.refresh!` keeps returning true/false, but now true means "the app has the latest release" (written, or already current), and it refuses releases it used to accept (see Safe refresh).
- `Model#image(year:)` sends `year` to the API instead of silently dropping it; the API answers `422 unsupported_filter` until year-accurate renders ship, so `image(year:)` is nil and `images_result` says why.
- A refreshed cache older than the gem's bundled data, or in a schema the gem does not read, is no longer served.
- `Model#to_h` gains `id`, `model_slug`, `forms`, `registration_years`; `ModelMatch#to_h` gains `id` and `confident`.

### Added
- **Safe refresh.** `Vehicles.refresh` returns a `Vehicles::RefreshResult` (`status` :updated/:current/:rejected/:failed, `reason`, `version`, `previous_version`, `message`; never raises). It reads the release manifest first (`config.manifest_url`, derived from `data_url`): an unsupported schema or an older version is refused and the same version downloads nothing. The payload is fetched from the announced release (jsDelivr `@latest` pinned to it), must carry that version and schema, match the manifest's per-kind model counts and its sha256 when published, keep every kind and (kind, country) slice at or above `config.refresh_min_ratio` (0.9) of the data in use, and pass the optional `config.refresh_guard`. Written atomically.
- **Every process adopts a new dataset on its own**: at most every `config.reload_check_interval` seconds (default 5) a call stats the file and reloads when it changed — no restart, no executor hook. A corrupt file never replaces the dataset in memory. `config.cache_dir` (or `VEHICLES_CACHE_DIR`) puts the cache on a shared volume, so one refresh reaches every container. README: "Staying current" has the multi-container recipe.
- **Canonical ids**: `Model#id` (`"car/volkswagen/golf"`), `Vehicles.by_id(id, follow: true)` (follows `former_ids`; a split id answers nil), `Vehicles.successor(id)` (the id to store now), `Vehicles.live?(id)`. Make `former_slugs` are read when the dataset publishes them (`Make#former_slugs`, `Vehicles.make("old-slug")`, `by_id` across a make rename); a no-op until then.
- **`kinds:`** on `Vehicles.model`, `match_model`, `identify` and `Make#model`: a hard filter on every rung, ids included (`identify("bus/iveco/daily", kinds: [:car])` → nil). `kind:` keeps scoping the name rungs and never overrides an explicit id.
- **`ModelMatch#confident?`**: an answer from a curated rung (exact, former_id, fold, alias, form, cleaned), never fuzzy or ambiguous — the recommended threshold for writing a match back without asking.
- **Per-country catalog**: `country:` on `Vehicles.catalog`, `makes`, `models`, `make_options` and `model_options` (models with official evidence there, in that country's own order). `top_models(limit: nil)` returns every match.
- **Labels in English and Spanish**: `Vehicles.color_options(locale: :es)`, `Color#label(:es)`, `Vehicles.kind_label` / `kind_options`, `Vehicles.body_type_label` / `body_type_options`. `Vehicles.color` resolves Spanish input ("Rojo", "marrón", "plateada", "granate").
- **Hosted errors are no longer silent**: `Model#images_result` returns a `Vehicles::HostedResult` (`reason`, `status`, the API's own `error` code, `url(size)`); `config.on_hosted_error` and a warn log line fire for 401/402/403/429/5xx/timeouts (never for a missing render). Image payloads are cached (`config.image_cache`, in-process by default; `image_cache_ttl` 1 day capped by the payload's `expires_at`, `image_miss_ttl` 10 min for 404s; errors never cached). `exact_color: true` answers nil instead of another color's render and remembers the palette so an unrendered color costs no request. ActiveSupport notifications `request.vehicles` / `refresh.vehicles` when present.
- `Model#registration_years`: the first..last year in official registrations when the dataset publishes it (nil until then). A hint, never a validation bound; `Model#years` docs now say plainly that production years are not published yet.
- Plates: `Match#reason` (`:ok`, `:unverifiable`, `:excluded_letters`, `:bad_shape`, `:empty`, `:unknown_jurisdiction` — the API's codes), `Match#excluded_letters`, `Match#passenger?` and `Series#passenger?` (issued to passenger-carrying vehicles; trailer and tractor series are not).
- Validators take `kind:`, `kinds:` and `country:` (`vehicle_make: { kind: :car, country: :es }`).
- `Plates::Match#near_misses`: the series whose shape a plate has but whose issuing alphabet it breaks ("1234 ABC" → `es-national-2000`: Spain issues no vowels, Ñ or Q). Empty whenever the plate hits a strict series. Lets a form explain the rejection. `Series#matching` and `Series#recall_lenient_regexp` back it, and `Series#letters` (the issued letter set, when the dataset enumerates one) tells a form whether the alphabet is what failed.

### Fixed
- The hosted client follows a former id's `301` (same origin only, so the key never leaves the host): images no longer vanish around a rename or a gem/API version skew.
- `Vehicles.regions` follows the dataset in effect (it was memoized once per process).
- Docs: the "car catalog is tens of KB" claim (it is ~63 KB worldwide, ~14 KB for one country), `Model::KINDS` ("all :car"), and the initializer's "EU market" text.
- **`Plates::Series#strict?` now reads the dataset's `matching:` key** (PRD-PLATES §2.7, normative) instead of inferring strictness from a `regex_strict` twin being present. The spec forbids that inference: most strict series need no twin because their `regex` already is the issuing grammar. 668 strict series were answering `strict? == false` before, among them Portugal's whole national range (AA-00-AA) and the Spanish CD/CC/OI/TA, military and police series. `Match#strict?` follows. Found by dogfooding: 2 of CarHey's 3 Portuguese cars validated as "recall-only".
- `Match#formatted` / `Series#format_serial` no longer invent a split when the series' regex can split a serial more than one way (`Series#ambiguous_split?`): "CD12345" and "CD123456" come back as stored instead of "CD-1234-5" / the representative "CD-123-456". This runs before the display-pattern walk; 22 series with variable-width groups (ES diplomatic, personalised and special-index plates) are affected.
- `Plates.template_series` (what `Plates.render` draws) prefers strict hits over recall-only ones: a Spanish "CD-123-456" is drawn as the diplomatic series, not as the 1900–1971 numeric catch-all it also fits.

### Changed
- Bundled data refreshed to VehiclesDB v2026.11.2 (and its 87-case conformance file): restyled names such as "León", "XCeed", "ProCeed".
- Bundled plates corpus refreshed to vehiclesdb `db0ec0a`: adds Egypt, Nigeria and Türkiye (127 jurisdictions, 1,409 series) and the Andorra and Austria verification corrections.

## [0.9.1] - 2026-11-09

### Changed
- Bundled data refreshed to VehiclesDB v2026.11.1: 15,635 models. Passenger versions of van-based MPVs now also publish in kind `car` (Caddy, Berlingo, Kangoo, Rifter, Tourneo Custom/Courier/Connect, Transit Custom, Doblò and more), plus the VW Multivan, GWM Ora 5, Ebro S800/S900, the Alfa Romeo 6C/8C classics and 24 typo-twin folds. Every retired id resolves through `former_ids`. Spanish new-car registrations landing on a published record go from 90.2% to 96.5%.

## [0.9.0] - 2026-11-09

### Changed

- **Behaviour change: `Vehicles.model(make, model)` now also answers a
  model's published aliases and its curated registry spellings** (the new
  `Model#forms`, below), after the name lookup misses. "Focus C-Max" is the
  Ford C-Max, "Megane Conquest" the Renault Arkana, "Qashqai +2" the Nissan
  Qashqai. This is curated data, not guessing: normalized equality, then
  spacing-blind equality; a spelling that two different models answer to
  returns nil. Every pair that resolved before resolves identically (the
  name lookup still runs first), so the only change is fewer nils. Found by
  dogfooding: 36 of the 41 make/model pairs our own CarHey app could not
  resolve were already curated in the open dataset, but never reached the
  gem. `fuzzy:` still governs the make typo tolerance only. The MCP
  `get_model` tool inherits this.
- **Bundled data refreshed to 2026.11.0** (15,629 models, 953 makes, 18
  countries) — the first release carrying `forms` (7,574 curated spellings).
- **The built-in make alias table is now empty** (`Dataset::BUILTIN_ALIASES`
  is kept, frozen and empty, for compatibility). Every nickname it held is a
  published dataset alias since 2026.11.0, so the JS/Python SDKs, the API and
  the widget agree with Ruby (RESOLUTION.md §1, "only published data counts").
  "range rover"/"rangerover" were dropped, not published: Range Rover is a Land
  Rover model family, not a make. Private nicknames belong in `config.aliases`.
- `Make#model` (and so the `vehicle_model` validator) is unchanged and stays
  strict: a form or a typo is not a model name to store. It now answers from
  per-make indexes built once on first use instead of normalizing every model
  name on every call; bulk lookups are about 10x faster (31.5k registry
  pairs: 38 s for `model` on 0.8.0, under 4 s for `model` plus `match_model`).

### Contract conformance (pre-release review)

- `Vehicles.identify`: a whole-text alias is refused only when ANOTHER record is
  named that — SEAT's "Málaga" alias on `seat/malaga` resolves ("malaga"),
  "Rabbit" (a Golf alias and `car/volkswagen/rabbit`'s name) stays nil.
- Machine-shaped input is checked per raw token, in both entry points: one
  slug-shaped token ("marcedes-benz gla", "New alpha-z") disables the typo
  rungs, exactly like the pair `marcedes-benz` + `GLA`.
- `match_model`: two DIFFERENT records with the same name answer `ambiguous`,
  never the first one (`Make#model` keeps its first match for the validator).
- `test/resolution_conformance_test.rb` runs the data repo's
  `conformance/resolve.json` (79 cases) — all pass on the bundled 2026.11.0.

### Added

- `Vehicles.match_model(make, model, kind: nil)` returns a
  `Vehicles::ModelMatch` (`model`, `rung`, `confidence`, `via`,
  `candidates`, `ambiguous?`), or nil when nothing matched at all. It follows
  the cross-surface resolution contract (vehiclesdb `RESOLUTION.md`) shared
  with the API, widget and SDKs. Rungs, strongest first: the name or slug by
  normalization, spacing-blind or "Serie 3" (`:fold`, 0.97); a published
  alias (`:alias`, 0.93); a curated form (`:form`, 0.92); the same after
  peeling a complete make name echoed into the model and leading "new"
  fillers ("Nuevo Citroën C4"; `:cleaned`, 0.90); a small unique typo of a
  name/alias/form ("Sirocco" → Scirocco; `:fuzzy`, 0.80). Any answer reached
  through a typo-corrected make is `:fuzzy` at 0.80 too. Confidences are fixed
  labels per rung, not probabilities. `to_h` reports the rung as
  `method: "fold"` etc., matching the API JSON. `via` records every
  transformation (`make_alias:`, `make_typo:`, `filler:`, `make_echo:`,
  `alias:`, `form:`, `fold:`, `model_typo:`, `kind_hint:`).
  Safety rules:
  - An ambiguous rung returns a ModelMatch with `model` nil and the competing
    `candidates`, and stops the ladder.
  - Typos never edit a word that contains a digit ("2008" stays a 2008) and
    never change short tokens ("Passat GT" is not the "Passat GL"). They allow
    one edit per word (two from nine letters) and never stack on a
    typo-corrected make.
  - Cleanup never peels a partial make name, or a word that is itself a model
    name ("Nova").
  - Id-, slug- and path-shaped input only takes the exact rungs.
  - There are no prefix or truncation heuristics.
- `Vehicles.identify(text, kind: nil)`: the contract's text entry point.
  It takes one free-text string and returns a `ModelMatch` or nil. It tries
  the canonical id verbatim (`:exact`, 1.0), then a former id (`:former_id`,
  0.98). Next it splits off the make (the longest leading run that is a make:
  exact splits first, then make typos) and runs the model ladder. Between the
  curated rungs and the heuristics, it accepts the whole text when it is
  exactly one model's published alias across all makes and no record is
  named that (`:alias`, 0.90). Apart from ids and whole-text aliases, nothing
  resolves without a make: "golf" is nil.
- A conformance runner (`test/resolution_conformance_test.rb`) that plays the
  contract's shared cases (`test/fixtures/conformance/resolve.json`, copied
  from the data repo) against the bundled dataset. It skips cases newer than
  the data and skips entirely while the file is absent.
- `Model#forms`: curated registry spellings that fold into the record
  (dataset key `forms`; `[]` on snapshots that predate it). Not part of
  `Model#to_h`.

## [0.8.0] - 2026-11-08

### Added

- **Plate art without sending the plate.** `Vehicles::Plates.render(registration,
  jurisdiction:, region: nil, label: nil)` draws a registration on its series'
  real VehiclesDB plate as an SVG, and nothing personal leaves the machine: the
  gem picks the series locally (the bundled matcher; the only standard-class
  hit, else the only hit — ambiguous plates such as German `MAB1234` answer
  nil instead of the wrong plate), derives the shape (`NNNN LLL`), fetches the
  BLANK template `GET {api_base_url}/plates/:code/:series_id/template.svg?shape=&region=`
  and fills it here. No API key is sent (the route is public). Returns nil on
  any failure, never raises.
- `Vehicles::Plates.template(code:, series:, shape: nil, region: nil)`: the
  blank template, or nil. Client-side fences refuse a shape that is not pure
  N/L classes and separators, so a registration passed by mistake never
  reaches the wire. Cached in-process by default; `config.plate_template_cache`
  takes any `read` / `write(key, value, expires_in:)` store (e.g. `Rails.cache`)
  and `config.plate_template_ttl` (default one day) the lifetime. Failures are
  remembered for five minutes, so an unreachable server costs one timeout per
  template per window, not one per call. Keys carry the template schema and
  gem version.
- `Vehicles::Plates::TemplateFill`: the reference filler, moved verbatim from
  vehiclesdb-web (`fill`, `metadata`, `groups`, and the shared fit formulas
  `fit_size` / `recentered_baseline` the VehiclesDB renderer will call from
  here), plus `shape_of` and a `label:` option for a localized accessible
  name. Standard library only; the file loads on its own in a gem-less Ruby.
- Templates are inlined into host pages, so both the fetch and
  `TemplateFill.fill` itself refuse a template carrying anything active or
  external (`<script>`, event handlers including `<svg/onload=…>`,
  `javascript:`, non-`data:` hrefs and `url()`s): `TemplateFill.inert?`.
- `region:` takes subdivision keys only (`75`, `2A`, `971`, `44-bzh`, `BY`,
  `ZH`, `9`), so a registration passed there by mistake is refused locally
  and never sent.

### Changed

- The HTTP plumbing (timeout, no silent retry, nil on failure) moved from
  `HostedProvider` into `Vehicles::HTTP`, shared by images and plate
  templates. Behaviour of the images calls is unchanged.

## [0.7.9] - 2026-11-08

### Fixed

- **Hosted images now reach the API.** `HostedProvider` requested
  `https://vehiclesdb.com/v1/vehicles/…/images`, but the VehiclesDB API lives
  under **`/api/v1`**: `/v1/…` is the website's HTML 404, so `Model#image` /
  `Model#images` returned nil for every key since 0.5.0. Requests now go to
  `GET {api_base_url}/api/v1/vehicles/:kind/:make_slug/:model_slug/images`
  (`HostedProvider::API_PREFIX`). `config.api_base_url` is still the origin
  and still overridable (`"http://localhost:3030"` for a local server); a
  trailing slash or a proxy path prefix on it is now kept as written
  instead of being dropped by `URI.join`. Pinned by tests over a real local
  socket: the exact request line, the Bearer header, and nil on a 404 HTML
  page, a 401, a non-JSON 200 and a refused connection.
- **One hosted request is one request.** Net::HTTP re-sends an idempotent
  GET once after a read timeout, so a slow images response was asked for
  twice: double the latency `api_timeout` promises to cap, and two billed
  calls when the second one is served (seen against a cold local server).
  `max_retries` is now 0; pinned by a socket test that counts connections.
- **A name that exists as several kinds answers with the car.**
  `Vehicles.model("Toyota", "Land Cruiser")` returned the **bus** (the first
  record of four kinds). Without `kind:`, `Make#model` / `Vehicles.model` /
  `Vehicles.find` now prefer the `:car` record and keep the first record
  when there is no car. Over every model name and slug in the bundled data
  this moves 51 names from bus to car — same make and model, never a
  different one.

### Added

- `kind:` on `Vehicles.model` and `Make#model` to pick the kind explicitly:
  `Vehicles.model("Toyota", "Land Cruiser", kind: :bus)`.
- **Spacing-blind model names.** When no name matches exactly, `Make#model`
  compares letters and digits only, so `"XCeed"` is Kia's `"X Ceed"`, `"A 5"`
  is Audi `"A5"`, `"CX5"` is `"CX-5"`, `"XC 90"` is `"XC90"` — but only when
  that lands on ONE name (never a guess between two), and never partially
  (`"X Cee"` stays nil). The model validator answers the same way: spacing
  is not a typo.
- **BMW's Spanish/Italian `"Serie N"`** reads as `"N Series"`
  (`Vehicles.model("BMW", "Serie 3")` → 3 Series); a real `"Serie …"` name
  (`"Serie X1"`) still wins.
- Measured on a Spanish carpooling app's 1,329 free-text vehicles (make/model
  typed or picked in Spanish): 17 more make/model pairs (23 vehicles) now
  resolve, and the 3 Land Cruisers resolve to the car. Internal double
  spaces were already collapsed by `Vehicles.normalize`; now pinned by a test.

### Changed

- `Model#years` / `Model#segment` no longer spend a request: the API serves
  no endpoint for them yet (the old `/v1/models/:slug` never existed), so
  the hosted provider answers nil without touching the network and the
  chain falls through to the local data, exactly as before. They light up
  when the API ships them. `HostedProvider.reset!` (its per-process cache)
  is gone with it.
- README: the plates endpoints are `/api/v1/plates/…`.

## [0.7.8] - 2026-10-10

### Added

- **Typo-tolerant make lookup.** `Vehicles.make`, `Vehicles.models` and
  every make-taking helper now fall back to the closest make by edit
  distance when nothing matches exactly: `"marcedes"` → Mercedes-Benz,
  `"volkswagon"` → Volkswagen, `"DeLorean"` → De Lorean. Bounded
  (Levenshtein 1 for 4-5 characters, 2 from 6 up, never under 4), stdlib
  only, and never a guess: when two different makes are equally close
  (`"Acra"`: Acura / Acma) the answer is `nil`. Exact, alias and slug
  matches always win; `Vehicles.find` runs its exact pass over every
  make/model split before retrying a misspelled make, so no answer that
  resolved in 0.7.7 changes. Opt out per call with `fuzzy: false`
  (`make`, `models`, `model`, `model_options`, `find`). Guards: optimal
  string alignment (an adjacent swap is one edit — `"telsa"` ties Tesla/
  Temsa → nil, never Temsa); a candidate never has fewer words than the
  query (`"Volvo V 60"` cannot become Volvo "60"); every word keeps its
  first letter (`"citroen e"` is not Citroën DS); the configured
  `other_label` is never fuzzy-matched. Verified: 0 changed / 0 lost
  answers over 37,050 `find` and 65,871 web-resolver-style queries.
- `Model#country_ranks` / `Model#rank_in(country)` — the model's rank
  among all models of its kind in that country (dataset key
  `country_ranks`, from `catalog/` `popularity.by_country[cc].rank`).
- `Model#mass_decile` — per-kind registration-mass decile (1 = heaviest),
  the dataset's `popularity.mass_decile` (2026.10.1+, pipeline#255 /
  ruling R3); nil-safe on older snapshots (the bundled 2026.10.0 has none).
  `global_decile` stays what it is — a presence average.
  `top_models(by: :mass_decile)` ranks by it (records without it are
  excluded, so it is `[]` on 2026.10.0 data); `by:` defaults to
  `:global_decile`; anything else raises ArgumentError. With `country:`
  the country's rank still sorts first (the decile breaks ties).
  `Model#to_h` gains `:mass_decile`.
- `rake "data:refresh[<tag>]"` — refreshes `data/vehicles.json` from a
  dataset release tag and writes `data/PROVENANCE-vehicles.md`; fills
  `country_ranks` from the same tag's catalog until the projection ships
  the key natively (then it asserts equality instead).

### Changed

- **`top_models(country:)` orders by that country's own rank.** Until now a
  country-filtered list kept the GLOBAL order (`global_decile`, a
  presence-weighted average across countries), so the UK top-10 read in
  everybody else's order. Models available there without a rank there
  follow in the old order; data without `country_ranks` degrades to the
  0.7.7 order. Ranks are per kind — pass `kind:` for a clean ranking.
- Bundled dataset refreshed 2026.07.4 → **2026.10.0** (14,997 models, 15
  countries; `dist/vehicles.json` at tag v2026.10.0 + `country_ranks`).
- The make and model validators stay EXACT (`fuzzy: false`): a typo never
  validates as a stored make.

- Fuzzy matching is for human-typed names only: Symbols, input containing
  `/`, `_`, `+` or `\` (ids, paths), hyphen-edged strings and single-case
  hyphenated slugs (`marcedes-benz`, `MARCEDES-BENZ`) resolve exactly or
  not at all; the MCP server's tools are exact-only.
- CI: the 111 rubocop offenses inherited from main are frozen (110 in a
  generated `.rubocop_todo.yml`, plus `plates/series.rb` in `.rubocop.yml`'s
  own ClassLength Exclude, which overrides the todo) — no code changes — so
  the Lint job is green again; new code is fully linted.

### Upgrade notes

- Apps that route or 404 on `Vehicles.make(param)`: slug-shaped params
  (`marcedes-benz`, anything with `/`, `_`, `+`, a Symbol) never fuzz, but
  a single-word param still does (`/makes/marcedes` → param `"marcedes"` →
  Mercedes-Benz). If a misspelled URL must 404 (or 301 to the canonical
  slug), call `Vehicles.make(param, fuzzy: false)` there.

## [0.7.7] - 2026-08-03

### Changed

- Plates dataset refreshed — the overnight swarm passes' settlements
  land: the Cypriot centre date mark, Brazil's square-dot printed form
  and photographed moto split, San Marino's structured legend/sigla
  fields, Ukraine's statutory line counts, California's pixel-sampled
  colours and corner-sticker guides, the Texas exempt restatement,
  Korea's corporate characters block, Thailand's seven-photo
  cross-check, and China's two-row trailer + NEV dedicated-mark flips
  (#288-#290).

## [0.7.5] - 2026-08-03

### Added

- `Plates.decode_table(name)` — the _decode lookups (district/office/
  use-mark tables) exposed to consumers, enabling serial-driven
  subregion resolution (renderers picking the right Land arms from a
  district prefix).

## [0.7.4] - 2026-08-03

### Added

- South Korea (21 series + hangul decode tables) — corpus: 124
  jurisdictions / 1,381 series.

## [0.7.3] - 2026-08-03

### Fixed

- Pattern-language literal escapes: ca-nb-truck-2003 introduced "\L"
  (a literal L, vs the any-letter placeholder). New Series#display_pattern
  resolves escapes for display and slot walks; the round-trip test
  substitutes placeholders escape-aware. Escape convention flagged to the
  data maintainers for a ruling.

## [0.7.2] - 2026-08-03

### Added

- The L3 wave: 28 jurisdiction files across five continents (jp cn in
  th my br mx ar nz za ua + Australia's 8 states + Canada's 13
  provinces/territories), 415 series and 10 more decode tables incl.
  Japan's 138-mark statutory office table. Corpus now: 123
  jurisdictions / 1,360 series / 34 decode tables.

## [0.7.1] - 2026-08-02

### Added

- Plates corpus refreshed to 91 jurisdictions (the EU/EEA wave-2 landing:
  ie dk no is pt lu pl cz sk hu ro si hr ee lv lt gr cy mt + microstates)
  with 22 decode tables.

## [0.7.0] - 2026-08-02

### Added

- The FULL plates corpus ships in the gem: 67 jurisdictions / 606 series
  (the 8-country L1 EU wave, all 50 US states + DC + 5 territories, and
  the redated pilots) + 10 decode tables — up from the 4 pilot files.
  The art tier stays in the data repo; the gem bundles format data.

## [0.6.4] - 2026-08-02

### Changed

- Bundled plates data refreshed from the redate pass: es-provincial is now
  1971-2000 pinned to Decreto 2046/1971 at both ends (was a 1999-2000
  instrument window), plus the 1900-1971 Spanish numeric era, the German
  1956-2000 DIN era, 11 German and 10 Florida period corrections — all
  cited to gazette primaries.
- `approximate_start?` covers the two new honesty vocabularies
  (instrument-in-force-upper-bound, secondary-locator-unverified), so
  upper-bounded and uncited-secondary starts render with the "~".

## [0.6.3] - 2026-08-02

### Changed

- Plate period labels read naturally: open series say "2000 → today", and
  instrument-dated starts mark approximation as "~1999" instead of the
  cryptic "≤1999". New `Series#approximate_start?` so displays can explain
  the tilde ("documented from this year; the format may be older").

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
