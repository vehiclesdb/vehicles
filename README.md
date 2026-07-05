# 🚗 `vehicles` – Car makes & models for your Rails app

[![Gem Version](https://badge.fury.io/rb/vehicles.svg)](https://badge.fury.io/rb/vehicles) [![Build Status](https://github.com/rameerez/vehicles/workflows/Tests/badge.svg)](https://github.com/rameerez/vehicles/actions)

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=vehicles)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=vehicles)!

`vehicles` gives your Rails app a clean, curated list of vehicle makes and models — **18.5k models across 900+ makes: cars, motorcycles, mopeds, vans, trucks and buses**, reconciled from official registers of 14 countries — ready for dropdowns, search, and validation. No API keys, no database table, no migration — it works **fully offline** the second you `bundle install`, because the data ships inside the gem. (Optionally, it can [refresh](#staying-current-optional) the data without a gem upgrade.)

✨ Perfect for marketplaces, carpooling & rideshare apps, fleet tools, parking & EV-charging apps, insurance and booking forms — anywhere a user has to pick their vehicle.

Check out my other 💎 Ruby gems: [`usage_credits`](https://github.com/rameerez/usage_credits) · [`profitable`](https://github.com/rameerez/profitable) · [`api_keys`](https://github.com/rameerez/api_keys) · [`nondisposable`](https://github.com/rameerez/nondisposable) · [`trackdown`](https://github.com/rameerez/trackdown)

## 👨‍💻 Example

```ruby
Vehicles.makes
# => ["Alfa Romeo", "Audi", "BMW", "BYD", "Citroën", "Cupra", "Dacia", "Fiat", ...]

Vehicles.models("VW")              # alias-aware — "VW" just works
# => ["Golf", "Polo", "Tiguan", "Passat", "T-Roc", "ID.3", "ID.4", "T-Cross", ...]

car = Vehicles.find("vw golf")     # one fuzzy lookup, make + model in a single string
car.make                           # => "Volkswagen"
car.name                           # => "Golf"
car.full_name                      # => "Volkswagen Golf"
car.kind                           # => :car
car.body_type                      # => :hatchback
car.hatchback?                     # => true
car.global_decile                  # => 2       (top 20% worldwide, measured from registrations)
car.available_in?(:nl)             # => true    (evidence in the Dutch register)

Vehicles.top_models(kind: :car, country: :nl, limit: 5).map(&:name)
# => the most popular models, from real registration counts
```

…and the whole reason this gem exists — a make → model picker in two lines:

```erb
<%= form.select :make,  Vehicles.make_options,             prompt: "Make" %>
<%= form.select :model, Vehicles.model_options(@car.make), prompt: "Model" %>
```

That's it. A working dropdown, with zero setup and zero network calls. You can finally delete that hand-maintained `MAKES = [...]` constant.

## Installation

Add it to your Gemfile:

```ruby
gem "vehicles"
```

And run `bundle install`. **That's the whole setup.** No generator, no migration, no API key, no seed task — the dataset is bundled and loaded lazily into memory on first use.

> [!NOTE]
> `vehicles` works in **any Ruby project**, not just Rails. The Rails bits (form option helpers, validators) light up automatically when Rails is present, and stay out of your way when it isn't.

## The basics

Two methods cover 90% of what you need:

```ruby
Vehicles.makes
# => ["Abarth", "Acura", "Alfa Romeo", ...]   (alphabetical, 900+ makes)

Vehicles.models("Toyota")
# => ["Yaris", "Corolla", "Aygo", "RAV4", "C-HR", "Prius", ...]
```

Make lookups are **forgiving by default** — case-insensitive, slug-friendly, and alias-aware, so whatever your users type tends to land:

```ruby
Vehicles.models("toyota")     # case-insensitive
Vehicles.models("VW")         # => Volkswagen   (common abbreviation)
Vehicles.models("merc")       # => Mercedes-Benz
Vehicles.models("alfa-romeo") # slug form
```

Unknown make? You get an empty array, never an exception:

```ruby
Vehicles.models("DeLorean")   # => []
```

## Smart lookup & search

When you want the rich object instead of a plain list, ask for it:

```ruby
make = Vehicles.make("Audi")     # => #<Vehicles::Make "Audi">
make.name                        # => "Audi"
make.slug                        # => "audi"
make.kinds                       # => [:car]
make.models                      # => ["A3", "A4", "Q3", "Q5", ...]
make.model("a3")                 # => #<Vehicles::Model "Audi A3">
```

`find` resolves a free-text "make + model" string into a single model — great for normalizing messy input:

```ruby
Vehicles.find("vw golf")          # => #<Vehicles::Model "Volkswagen Golf">
Vehicles.find("Mercedes C Class") # => #<Vehicles::Model "Mercedes-Benz C-Class">
Vehicles.find("nope nope")        # => nil
```

`search` returns every model that matches, ranked — perfect for an autocomplete endpoint:

```ruby
Vehicles.search("golf")
# => [#<Model "Volkswagen Golf">]

Vehicles.search("3")
# => [#<Model "BMW 3 Series">, #<Model "Mazda 3">, #<Model "Citroën C3">, ...]
```

Every `Vehicles::Model` reads like English and serializes cleanly:

```ruby
car = Vehicles.find("seat leon")
car.make        # => "SEAT"
car.name        # => "Leon"
car.full_name   # => "SEAT Leon"
car.slug        # => "seat-leon"
car.to_h        # => { make: "SEAT", model: "Leon", slug: "seat-leon",
                #      kind: :car, body_type: :hatchback, global_decile: 2,
                #      availability: ["es", "fi", "gb", ...] }
```

## Kinds & body types

Every vehicle is classified on two axes, so you can filter, group, and label without maintaining your own taxonomy.

**`kind`** — what *sort* of vehicle it is. Sourced straight from official registration data. Six kinds ship today:

```ruby
Vehicles.kinds   # => [:bus, :car, :moped, :motorcycle, :truck, :van]
```

**`body_type`** — the sub-classification *within* a kind:

```ruby
# cars   :hatchback :sedan :wagon :suv :mpv :coupe :convertible :roadster :pickup :van
```

```ruby
Vehicles.find("vw tiguan").kind        # => :car
Vehicles.find("vw tiguan").body_type   # => :suv
Vehicles.find("vw tiguan").suv?        # => true   ← predicate sugar for every body_type
Vehicles.find("yamaha mt-07").kind     # => :motorcycle
Vehicles.find("yamaha mt-07").two_wheeler?  # => true  (motorcycle OR moped — picker unions)
```

Filter any list by either axis:

```ruby
Vehicles.models("Toyota", body_type: :suv)   # => ["RAV4", "C-HR", "Yaris Cross", ...]
Vehicles.makes(kind: :car)                    # => makes that build cars
Vehicles.makes(kind: :motorcycle)             # => makes that build bikes
Vehicles.search("golf").select(&:hatchback?)
```

> [!NOTE]
> `body_type` is honest: cars always carry one; other kinds return `nil` until
> an honest vocabulary exists for them (a truck is not a "hatchback"). The
> predicates just return `false` on `nil`, so your filters never crash. Market
> *segments* (supercar, city car, …) are an editorial layer that arrives with
> [VehiclesDB](#-more-with-vehiclesdb).

## Popularity & availability

Every model carries two open-data signals, measured from official registers
(never scraped, never guessed):

```ruby
car = Vehicles.find("toyota corolla")
car.global_decile      # => 1        1 = top 10% worldwide … 10; nil = unranked
car.popular?           # => true     decile ≤ 2 (and `false` when unranked — honest)
car.availability       # => ["es", "fi", "gb", ...]   countries with official evidence
car.available_in?(:th) # => true

# The most popular models — perfect for "common choices" pre-filled pickers:
Vehicles.top_models(kind: :car, country: :nl, limit: 10)   # => [Model, ...]
Vehicles.top_models(kind: :motorcycle, limit: 10).map(&:full_name)
```

`availability` means *an official source evidences the model there* (register,
type approval, or sales reporting) — presence, not marketing history: grey
imports count, because they're real vehicles on real roads.

## MCP server for AI agents

The gem ships `vehicles-mcp` — a read-only [MCP](https://modelcontextprotocol.io)
server over the bundled dataset, so your agents ground themselves in real
vehicle data instead of hallucinating nameplates. No network, no keys:

```json
{ "mcpServers": { "vehicles": { "command": "vehicles-mcp" } } }
```

Tools: `search_makes` · `search_models` · `get_model` · `top_models`. Works
anywhere MCP does (Claude Code, Claude Desktop, Cursor, …) the moment the gem
is installed.

## Colors

A small **canonical color palette** ships with the gem — the handful of colors
that cover virtually every car, plus an explicit `other`. It's the shared
vocabulary for color dropdowns today and for color-accurate imagery from the
hosted API later, so "red" means the same thing everywhere.

```ruby
Vehicles.colors
# => [#<Color white "White" #F4F4F4>, #<Color black "Black" #1B1B1B>, ...]

Vehicles.color("navy")          # forgiving: synonyms, case, diacritics
# => #<Vehicles::Color blue "Blue" #27408B>
Vehicles.color("navy").slug     # => "blue"   ← the stable value you store
Vehicles.color("navy").hex      # => "#27408B" (representative swatch)

Vehicles.color_options          # => [["White", "white"], ["Black", "black"], ...]
```

Names are English — store the **slug** and localize the label in your app (the
slug is also what maps to image color-variants down the line).

## Rails dropdowns

The `*_options` helpers return `[[label, value], ...]` pairs, exactly what Rails' `select` wants:

```ruby
Vehicles.make_options
# => [["Alfa Romeo", "alfa-romeo"], ["Audi", "audi"], ["BMW", "bmw"], ...]

Vehicles.model_options("audi")
# => [["A3", "a3"], ["A4", "a4"], ["Q3", "q3"], ...]
```

### Dependent make → model picker

The whole dataset is small, so the simplest, snappiest way to wire a dependent
picker is **client-side**: embed [`Vehicles.catalog`](#the-full-ruby-api) once and
switch the model list with no request at all — **no route, no controller, no
fetch.**

```erb
<div data-controller="vehicle-picker"
     data-vehicle-picker-catalog-value="<%= Vehicles.catalog.to_json %>">
  <%= form.select :make,  Vehicles.makes,             { include_blank: "Make" },
        data: { vehicle_picker_target: "make", action: "change->vehicle-picker#makeChanged" } %>
  <%= form.select :model, Vehicles.models(@car&.make), { include_blank: "Model" },
        data: { vehicle_picker_target: "model" } %>
</div>
```

```js
// app/javascript/controllers/vehicle_picker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["make", "model"]
  static values  = { catalog: Object }   // { "Audi": ["A3", ...], ... }

  makeChanged() {
    const models = this.catalogValue[this.makeTarget.value] || []
    const previous = this.modelTarget.value
    this.modelTarget.replaceChildren(new Option("Model", ""))
    for (const name of models) {
      this.modelTarget.add(new Option(name, name, false, name === previous))
    }
  }
}
```

That's the whole picker — the gem ships the data, you keep your markup and ~12
lines of JS. (Storing slugs instead of names? Swap the selects for
`make_options` / `model_options` and key the catalog by slug.)

> [!TIP]
> Prefer a server round-trip (huge/remote dataset, or you'd rather not embed it)?
> It's a three-line endpoint — `render json: Vehicles.models(params[:make])` — and
> the controller fetches that on `makeChanged` instead of reading the embedded
> catalog. Same gem API, your call.

## Validations

Drop-in ActiveModel validators, so bad data never reaches your database:

```ruby
class Car < ApplicationRecord
  validates :make,  vehicle_make: true                 # must be a real make
  validates :model, vehicle_model: { make: :make }     # must be a real model of that make
end
```

```ruby
Car.new(make: "Volkswagen", model: "Golf").valid?      # => true
Car.new(make: "Volkswagen", model: "Mustang").valid?   # => false
Car.new(make: "Tesler",     model: "Model 3").valid?   # => false
```

They're forgiving the same way the lookups are (aliases, case, slugs), and they never raise on blank/garbage input — they just add an error.

## Recommended integration

Here's the pattern that works cleanly end to end — and a reference schema for the
columns a vehicle record actually needs.

**A record stores its vehicle's *identity*, not the reference data.** Make,
model, year, and color identify the car; `kind` and `body_type` (and, later,
specs/images) are *properties of that make+model* owned by the dataset — look
them up via the gem, don't duplicate them per row (they'd just drift). So the
schema is small and stable:

| Column   | Type      | Store                                   | Example       |
|----------|-----------|-----------------------------------------|---------------|
| `make`   | `string`  | display name                            | `"Volkswagen"`|
| `model`  | `string`  | display name                            | `"Golf"`      |
| `year`   | `integer` | the year                                | `2022`        |
| `color`  | `string`  | a canonical color **slug**              | `"blue"`      |

Everything else (`kind`, `body_type`, production years, images, …) is derived:
`Vehicles.model(record.make, record.model)`. No `kind`/`body_type` columns, no
migration to add new metadata later — it lands in the dataset, not your schema.

**Store the display name.** The simplest, most readable thing to persist is the
name itself (`"Volkswagen"`, `"Golf"`). Populate the selects with the plain
**name lists**, where the option value *is* the name:

```erb
<%= form.select :make,  Vehicles.makes,             { include_blank: "Make" } %>
<%= form.select :model, Vehicles.models(@car.make), { include_blank: "Model" } %>
<%= form.select :year,  (Date.current.year + 1).downto(1990).to_a, { include_blank: "Year" } %>
<%= form.select :color, Vehicles.color_options,     { include_blank: "Color" } %>
```

> [!TIP]
> Use `Vehicles.makes` / `Vehicles.models` (name = value) when your column stores
> the **display name**. Use `Vehicles.make_options` / `Vehicles.model_options`
> (which pair `[name, slug]`) only when you store the **slug** — then read the
> name back with `Vehicles.make(slug).name`. Pick one and stay consistent.

**Validate what you store** — the dropdowns already constrain input, but the
validators guard every other write path (imports, console, your own API):

```ruby
validates :make,  vehicle_make: true,             allow_blank: true
validates :model, vehicle_model: { make: :make }, allow_blank: true
validates :color, inclusion: { in: Vehicles.colors.map(&:slug) }, allow_blank: true
```

**Read the metadata back** from a stored pair whenever you need it — kind,
body type, and (with the hosted API) years/segment/image:

```ruby
car = Vehicles.model(record.make, record.model)   # => Vehicles::Model | nil
car&.body_type                                      # => :hatchback
car&.suv?                                           # => false
```

**Only accept the kinds you support.** Filter every list/lookup by `kind:` so
the picker only ever offers vehicles your app handles — and widening later (when
new kind packs ship, or when you decide to accept them) is a one-word change, not
a migration:

```ruby
Vehicles.makes(kind: :car)                 # makes that build cars
Vehicles.models("Toyota", kind: :car)      # ...their cars only
```

No migration, no seed task, no API key — the data is bundled and read from
memory. The whole integration is the markup above plus a 3-line endpoint for the
dependent model list (see [Rails dropdowns](#rails-dropdowns)).

## Country & region awareness

Vehicle availability is regional — a Vauxhall in the UK is an Opel on the continent, a Perodua exists in Malaysia and almost nowhere else. `vehicles` models this per country, from evidence:

```ruby
Vehicles.find("perodua myvi").availability      # => ["gb", "my"]
Vehicles.find("vw golf").available_in?(:nz)     # => true
Vehicles.top_models(kind: :car, country: :es)   # country-scoped popularity
```

The bundled snapshot is **global** (official registers of 14 countries across
Europe, North America, SE Asia, Oceania and Ukraine — see [Where the data
comes from](#where-the-data-comes-from)), so the region gate accepts every
region query — `region: :eu` callers from 0.1.x keep working unchanged:

```ruby
Vehicles.makes(region: :eu)   # fine — a global snapshot covers the EU
Vehicles.region               # => :global
```

## 🔓 More with VehiclesDB

`vehicles` is the free, open-source SDK for [**VehiclesDB**](https://vehiclesdb.com) — a hosted API for richer vehicle data. The gem is **fully standalone and always will be**; pointing it at VehiclesDB is purely additive. Drop in an API key and the same objects you already use light up with more:

```ruby
Vehicles.configure do |config|
  config.api_key = ENV["VEHICLESDB_API_KEY"]   # optional — unlocks hosted data
end

car = Vehicles.find("vw golf")
car.years                       # => 1974..2024            production years
car.segment                     # => :hatchback / :hot_hatch   editorial segment
car.image                       # => "https://cdn.vehiclesdb.com/volkswagen/golf.webp"
car.image(year: 2020)           # year-accurate photo
car.image(year: 2020, color: :silver)
```

Under the hood this is a simple **provider** model: a `LocalProvider` (the bundled data) is always available, and a `HostedProvider` activates only when an API key is configured. Calls prefer the hosted data when it's there and **fall back to the local data otherwise — never raising, never blocking** your request:

```ruby
car.image     # no API key configured?  => nil   (your views just render a placeholder)
car.years     # not in the local pack yet? => nil, until you add a key or we ship it locally
```

So you can build your UI against the full API today, ship on the free local data, and flip on richer data later without touching your code.

## Configuration

Everything has a sensible default; you can run the gem without configuring anything. When you do want to tune it:

```ruby
# config/initializers/vehicles.rb
Vehicles.configure do |config|
  config.region    = :eu                          # default region for queries
  config.api_key   = ENV["VEHICLESDB_API_KEY"]    # optional hosted VehiclesDB data
  config.aliases   = { "Chevy" => "Chevrolet" }   # add your own make aliases
  config.use_cache = true                         # prefer a refreshed dataset over the bundled one
end
```

## Staying current (optional)

The bundled snapshot works offline forever — but vehicle data changes (new
makes, fixes), and you shouldn't have to ship a gem upgrade to every app just to
get them. So `vehicles` can **refresh** from the published
[dataset](https://github.com/vehiclesdb/vehiclesdb) into a local file cache;
loads prefer the cache over the bundled copy. Data fixes reach your app **without
a gem bump.**

`rails g vehicles:install` drops a `VehiclesRefreshJob` — schedule it (daily is
plenty), e.g. with solid_queue:

```yaml
# config/recurring.yml
vehicles_refresh:
  class: VehiclesRefreshJob
  schedule: every day at 3am
```

Or refresh manually:

```ruby
Vehicles.refresh!     # pull latest -> cache; true/false, never raises
Vehicles.data_version # => the version now in effect (cached, or bundled)
```

It's safe by design: a failed/partial download never replaces good data, and the
gem keeps serving the cache (or the bundled snapshot) no matter what. Want it
fully offline/deterministic? `config.use_cache = false`.

## The full Ruby API

```ruby
# Lists (strings — drop straight into a form)
Vehicles.makes                          # => [String]
Vehicles.makes(kind: :car, region: :eu)
Vehicles.models("Audi")                 # => [String]
Vehicles.models("Audi", body_type: :suv)

# Option pairs (for Rails `select`)
Vehicles.make_options                   # => [[label, value]]
Vehicles.model_options("Audi")          # => [[label, value]]

# Whole make => [models] map (embed once for a client-side dependent picker)
Vehicles.catalog(kind: :car)            # => { "Audi" => ["A3", ...], ... }

# Objects
Vehicles.make("Audi")                   # => Vehicles::Make | nil
Vehicles.find("audi a3")                # => Vehicles::Model | nil  (one free-text string)
Vehicles.model("Audi", "A3")            # => Vehicles::Model | nil  (a stored make+model pair)
Vehicles.search("a3")                   # => [Vehicles::Model]

# Popularity & availability (open data, measured from official registers)
Vehicles.kinds                          # => [:bus, :car, :moped, :motorcycle, :truck, :van]
Vehicles.top_models(kind: :car, country: :nl, limit: 10)  # => [Vehicles::Model]

# Vehicles::Make
make.name      make.slug      make.aliases     make.kinds
make.models    make.model("a3")                make.to_h

# Vehicles::Model
model.make     model.name     model.full_name  model.slug    model.to_h
model.kind     model.body_type                 model.suv?    model.coupe?   # …predicates
model.global_decile   model.popular?           # 1 = top 10% worldwide; nil-safe
model.availability    model.available_in?(:nl) model.two_wheeler?
model.years    model.segment  model.image(year:, color:)     # ← hosted VehiclesDB API

# Colors (canonical palette)
Vehicles.colors                         # => [Vehicles::Color]
Vehicles.color("navy")                  # => Vehicles::Color | nil (forgiving)
Vehicles.color_options                  # => [[name, slug]]  (for select)
color.slug     color.name     color.hex

# Meta
Vehicles.data_version                   # => "2026.07.0"   (version in effect: cached or bundled)
Vehicles.region                         # => :global

# Refresh (optional — keep data current without a gem upgrade)
Vehicles.refresh!                       # pull latest published data -> cache; true/false, never raises
Vehicles.reload!                        # drop the in-memory dataset (reload from disk)
```

## Where the data comes from

The bundled dataset is [**VehiclesDB**](https://github.com/vehiclesdb/vehiclesdb) — an open dataset **reconciled from official vehicle registers of 14 countries on 4 continents** (the Dutch RDW, UK DfT, Spanish DGT, Finnish Traficom, German KBA, US EPA, New Zealand's Motor Vehicle Register, Thailand's DLT, Ukraine's MVS, and more). A model ships only when **two independent official sources corroborate it** — or one shows a registration count no typo could produce — so you get real nameplates without the registry noise.

Every record is shaped like this:

```json
{
  "name": "Volkswagen", "slug": "volkswagen", "kinds": ["car", "van"],
  "models": [
    { "name": "Golf", "slug": "golf", "kind": "car", "body_type": "hatchback",
      "global_decile": 2, "availability": ["ca", "es", "fi", "gb", "nl", "..."] }
  ]
}
```

- **`kind` is sourced, not guessed** — straight from each register's official classification. **`body_type` is curated** on top (registers lump wagons, SUVs and crossovers together), mapped to a clean canonical vocabulary.
- **Nameplate-level, on purpose.** "Golf" covers the GTI, the Variant, the R — that's what a dropdown wants. Two-wheelers keep displacement granularity ("Wave110i", "CBR600RR") because that's how riders and registers both speak. Per-trim and per-generation detail is a VehiclesDB API concern.
- **Popularity is measured**, from real registration/fleet counts — never scraped rankings. **Availability is evidence** (a country appears because an official source shows the model there), not marketing history.
- **Source data:** openly-licensed government sources only, every license pinned and verified at build time — [full source list](https://github.com/vehiclesdb/vehiclesdb/blob/main/SOURCES.md) and [attribution notices](https://github.com/vehiclesdb/vehiclesdb/blob/main/ATTRIBUTION.md).
- **This dataset** (`data/vehicles.json`): **CC-BY 4.0**. Attribution: *"Vehicle data by VehiclesDB (CC-BY 4.0), built from official public registers."*
- **The gem code:** MIT.

The data is versioned (`Vehicles.data_version`). Each gem release bundles a known snapshot — the offline, deterministic floor. To get newer data, either upgrade the gem or enable [refresh](#staying-current-optional) (which pulls published releases without a gem bump). Either way it's explicit and versioned — no silent mutations.

## How it works

No magic, just good defaults:

- **Bundled, not fetched.** `data/vehicles.json` is packaged in the gem and loaded into a frozen, memoized in-memory index on first access. First call builds the index; every call after is a hash lookup. No HTTP, no SQLite, no ActiveRecord on the read path.
- **Zero-config.** No initializer required. No migration. Nothing to schedule.
- **Standalone first, SDK second.** The hosted VehiclesDB layer is strictly optional and detected at runtime; the gem never hard-depends on it.
- **Rails-aware, not Rails-bound.** Form helpers and validators register through a lightweight Railtie only when Rails is loaded.

## Roadmap

Bundled today: 19k models across 6 kinds and 14 countries, with popularity +
availability, plus the MCP server. On the way:

- 🌍 More **countries** (Switzerland next; the dataset grows monthly)
- 📅 Production **years** in the local data
- 🧬 **Generations & variants** layers (the schema already reserves them)
- 🖼️ Model **images** (via VehiclesDB)
- 🏷️ **Segments** (supercar, city car, hot hatch) and richer metadata
- 🔎 A mountable **autocomplete endpoint** so the dependent-dropdown recipe becomes one line

Want one of these sooner? Open an issue.

## Testing

Run the test suite with `bundle exec rake test`. The gem is tested against multiple Rails versions with Appraisal: `bundle exec appraisal rails-8.0 rake test`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/vehicles. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). The bundled dataset is licensed CC-BY 4.0 (see [Where the data comes from](#where-the-data-comes-from)).
