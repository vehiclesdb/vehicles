# 🚗 `vehicles` – Car makes & models for your Rails app

[![Gem Version](https://badge.fury.io/rb/vehicles.svg)](https://badge.fury.io/rb/vehicles) [![Build Status](https://github.com/vehiclesdb/vehicles/workflows/Tests/badge.svg)](https://github.com/vehiclesdb/vehicles/actions)

> **Get your free key, the integration guide and the credit snippet at [vehiclesdb.com](https://vehiclesdb.com/users/sign_up?for=app_saas&cta=readme_vehicles)**

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=vehicles)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=vehicles)!

`vehicles` gives your Rails app a clean, curated list of vehicle makes and models — **every make and model in the VehiclesDB open dataset: cars, motorcycles, mopeds, vans, trucks and buses**, reconciled from the official vehicle registers of every country the dataset covers (current counts: [vehiclesdb.com/makes](https://vehiclesdb.com/makes), or `manifest.json` in the data repo) — ready for dropdowns, search, and validation. No API keys, no database table, no migration — it works **fully offline** the second you `bundle install`, because the data ships inside the gem. (Optionally, it can [refresh](#staying-current-optional) the data without a gem upgrade.)

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
# => ["Abarth", "Acura", "Alfa Romeo", ...]   (alphabetical, every make)

Vehicles.models("Toyota")
# => ["Yaris", "Corolla", "Aygo", "RAV4", "C-HR", "Prius", ...]
```

Make lookups are **forgiving by default** — case-insensitive, slug-friendly, and alias-aware, so whatever your users type tends to land:

```ruby
Vehicles.models("toyota")     # case-insensitive
Vehicles.models("VW")         # => Volkswagen   (common abbreviation)
Vehicles.models("merc")       # => Mercedes-Benz
Vehicles.models("alfa-romeo") # slug form
Vehicles.models("marcedes")   # => Mercedes-Benz (typo: one make is clearly closest)
```

Typos resolve too: when nothing matches exactly, the closest make within a small edit distance wins (1 edit up to 5 characters, 2 from 6 up, none under 4) — but only if ONE make is closest, so `"Acra"` (one edit from both Acura and Acma) stays `nil` rather than guessing. Pass `fuzzy: false` (`Vehicles.make("marcedes", fuzzy: false) # => nil`) when you need exact-only matching; the validators always do, so a typo never validates as a stored make. Three more guards keep it from guessing: a swap of two neighbouring letters counts as one edit (`"telsa"` is equally close to Tesla and Temsa, so it stays `nil`); a match may not drop a whole word (so `"Volvo V 60"` never turns into Volvo "60"); and every word keeps its first letter (so `"citroen e"` is not Citroën DS). Your configured `other_label` never fuzzy-matches a real make. Machine input never fuzzes either: Symbols, anything with `/`, `_`, `+` or `\` (ids like `car/mercedes-benz/c-class`, paths like `/makes/marcedes`), and single-case hyphenated slugs (`marcedes-benz`, `MARCEDES-BENZ`) resolve exactly or return `nil` — so routes and stored ids can never land on a guessed make. The MCP server tools are exact-only.

Unknown make? You get an empty array, never an exception:

```ruby
Vehicles.models("Zzyzx Motors")   # => []
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

### Matching stored make + model pairs

Records that keep make and model in separate columns resolve with `model`. Since 0.9.0 it also answers the model's published aliases and its **curated registry spellings** (`Model#forms`: how registries and people actually type the model, curated per make in the open dataset — never ambiguous within a make):

```ruby
Vehicles.model("Ford", "Focus C-Max")        # => #<Vehicles::Model "Ford C-Max">       (a curated form)
Vehicles.model("Renault", "Megane Conquest") # => #<Vehicles::Model "Renault Arkana">  (not the Megane)
Vehicles.model("Nissan", "Qashqai +2")       # => #<Vehicles::Model "Nissan Qashqai">  (a published alias)
Vehicles.model("Ford", "C-Max").forms        # => ["4D Focus C-Max", "C-Max Energi", "Cmax", ...]
```

For messy free text, `match_model` goes further and tells you **how** it matched, so you decide what to trust:

```ruby
m = Vehicles.match_model("VW", "Tuareg")
m.model       # => #<Vehicles::Model "Volkswagen Touareg">
m.rung        # => :fuzzy
m.confidence  # => 0.8
m.via         # => ["make_alias:vw→volkswagen", "model_typo:tuareg→touareg"]
m.candidates  # => every kind of the answer ([car], or [car, van, bus] for a Land Cruiser)

Vehicles.match_model("Citroën", "Nuevo Citroën C4").via
# => ["filler:nuevo", "make_echo:citroen"]

Vehicles.match_model("Toyota", "Corola")      # => ambiguous: Corolla or Corona?
# .model => nil, .ambiguous? => true, .candidates => [Corolla, Corona]

Vehicles.match_model("Honda", "Honda")        # => nil (a make, not a model)
Vehicles.match_model("Peugeot", "2009")       # => nil (never "the 2008", never "the 208")
```

It tries, strongest first, and stops at the first rung that answers:

| `rung` | what matched | confidence |
|---|---|---|
| `:fold` | the name or slug (`make.model`): by normalization, spacing-blind ("XCeed" = "X Ceed"), or "Serie 3" = "3 Series" | 0.97 |
| `:alias` | a published model alias | 0.93 |
| `:form` | a curated registry spelling (`Model#forms`) | 0.92 |
| `:cleaned` | the above after peeling a complete make name typed into the model ("Citroën C3", "Lynk And Co 01") and leading "new" words (nuevo/nueva/new/neu/neue/nouveau/nouvelle/nuovo/nuova/novo/nova) | 0.9 |
| `:fuzzy` | a small, unique typo of a name, alias or form ("Sirocco", "Tuareg", "Mustnag") — and anything found behind a typo-corrected make ("Volkswagon") | 0.8 |

`confidence` is a fixed label per rung, not a measured probability: use it as a threshold ("auto-accept ≥ 0.9, ask the user below"). `to_h` reports the rung as `method: "fuzzy"`, the same field and values as the VehiclesDB API and SDKs: every surface follows one resolution contract and runs the same conformance cases. The rules that keep it from ever guessing:

- **Ambiguity stops the ladder.** If the data knows two answers (a spelling claimed by two models, a typo equally close to two), you get `ambiguous?` with the `candidates` — a weaker rung never overrules it.
- **Typos never touch numbers or codes.** A word containing a digit must match exactly ("2008" ≠ "208", "TRX250R" ≠ "TLR250R"); short tokens never change ("Passat GT" is not the "Passat GL"); one edit per word (two only in long words); never on top of a typo-corrected make.
- **No guessing from prefixes.** "C3 Aircr" is not "C3" (it's the C3 Aircross); only a curated form can say so.
- **Ids stay exact.** Slug-, id- and path-shaped input (`"golf-gti"`, `"car/volkswagen/golf"`, symbols) only takes the exact rungs.

`make.model(...)` and the `vehicle_model` validator stay strict — a form or a typo is not a valid model name to store.

**Safe to write back without asking?** `confident?` is the recommended auto-apply threshold: an answer (not ambiguous) from a curated rung — the id, a former id, the name, a published alias, a curated form, or one of those after `:cleaned`. Never `:fuzzy`: a typo correction is a guess to *show* the user ("did you mean Touareg?"), not to store silently.

```ruby
m = Vehicles.match_model(row.make, row.model, kind: :car)
row.update!(make: m.model.make, model: m.model.name, vehiclesdb_id: m.model.id) if m&.confident?
```

**Kinds.** One nameplate can be several records (Iveco's Daily is a van, a truck and a bus). That is not ambiguity: without a kind, every VehiclesDB surface (gem, API, SDKs, widget) applies the same rule — the record with the lowest `mass_decile`, then van → car → bus → truck → moped → motorcycle, then the id — so "Iveco Daily" is the van everywhere (`Vehicles::KindRule`; until 0.9.1 the gem preferred the car). Pass `kind:` to choose one, or `kinds:` to allow only some: a record outside `kinds:` never answers, on any rung, ids included.

```ruby
Vehicles.model("Iveco", "Daily")                     # => the van
Vehicles.model("Iveco", "Daily", kind: :bus)          # => the bus
Vehicles.match_model("Iveco", "Daily", kinds: [:car]) # => nil (there is no car Daily)
Vehicles.identify("bus/iveco/daily", kinds: [:car])   # => nil (an id outside the scope too)
Vehicles.identify("bus/iveco/daily", kind: :car).model # => the bus: `kind:` never overrides an explicit id
```

One free-text string instead of a pair? `identify` splits off the make (the longest leading run that is a make) and runs the same ladder. It also takes canonical ids (`:exact`, 1.0), ids a record has replaced (`:former_id`, 0.98), and a whole string that is exactly one model's published alias (`:alias`, 0.90). Apart from those, nothing resolves without a make:

```ruby
Vehicles.identify("vw tuareg").model          # => #<Vehicles::Model "Volkswagen Touareg"> (:fuzzy)
Vehicles.identify("car/volkswagen/golf").rung # => :exact
Vehicles.identify("1er").model                # => #<Vehicles::Model "BMW 1 Series"> (:alias, 0.9)
Vehicles.identify("golf")                     # => nil (no make)
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
car.id          # => "car/seat/leon"   ← the canonical id: store this
car.make        # => "SEAT"
car.name        # => "León"
car.full_name   # => "SEAT León"
car.slug        # => "seat-leon"
car.to_h        # => { id: "car/seat/leon", make: "SEAT", model: "León", slug: "seat-leon",
                #      kind: :car, body_type: :hatchback, global_decile: 2,
                #      availability: ["es", "fi", "gb", ...], ... }
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

Labels for a kind or body type `<select>` ship in English and Spanish (you store the symbol):

```ruby
Vehicles.kind_options(locale: :es)          # => [["Autobús", "bus"], ["Camión", "truck"], ["Ciclomotor", "moped"], ["Coche", "car"], ...]
Vehicles.kind_label(:van, locale: :es)      # => "Furgoneta"
Vehicles.body_type_label(:wagon, locale: :es) # => "Familiar"
Vehicles.body_type_options(locale: :es)     # => [["Compacto", "hatchback"], ["Berlina", "sedan"], ...]
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

# The most popular models — perfect for "common choices" pre-filled pickers.
# With `country:`, ordered by THAT country's own registration rank (ranks are per kind,
# so pass `kind:`; countries whose sources record presence only — us, ca for cars —
# have no ranks and keep the global order):
Vehicles.top_models(kind: :car, country: :gb, limit: 3).map(&:name)  # => ["Fiesta", "Golf", "Corsa"]
Vehicles.find("vw golf").rank_in(:gb)   # => 2    rank among all GB cars (nil where unranked)

# Two different "popularity" questions — pick the one you mean:
car.global_decile      # presence average: "popular in MANY countries" (equal country weight)
car.mass_decile        # registration mass per kind: "how many EXIST" (1 = heaviest 10%)
                       #   nil until your data is 2026.10.1+ (refresh! or a newer gem)
Vehicles.top_models(kind: :car, by: :mass_decile, limit: 10)  # [] on older snapshots
Vehicles.top_models(kind: :motorcycle, limit: 10).map(&:full_name)
```

`availability` means *an official source evidences the model there* (register,
type approval, or sales reporting) — presence, not marketing history: grey
imports count, because they're real vehicles on real roads.

## MCP server for AI agents

> **Get your free key, the integration guide and the credit snippet at [vehiclesdb.com](https://vehiclesdb.com/users/sign_up?for=ai_app&cta=readme_vehicles_mcp)**

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

Vehicles.color_options               # => [["White", "white"], ["Black", "black"], ...]
Vehicles.color_options(locale: :es)  # => [["Blanco", "white"], ["Negro", "black"], ["Gris", "grey"], ...]
Vehicles.color("red").label(:es)     # => "Rojo"
Vehicles.color("Marrón").slug        # => "brown"  — Spanish input resolves too ("rojo", "plateada", "granate")
Vehicles.colors(locale: :es).first   # => #<Vehicles::Color white "Blanco" #F4F4F4>
```

Store the **slug** (it is also what maps to the image color variants); labels
ship in English and Spanish (`locale: "es-MX"` folds to `:es`; other locales
fall back to English).

## Rails dropdowns

The `*_options` helpers return `[[label, value], ...]` pairs, exactly what Rails' `select` wants:

```ruby
Vehicles.make_options
# => [["Alfa Romeo", "alfa-romeo"], ["Audi", "audi"], ["BMW", "bmw"], ...]

Vehicles.model_options("audi")
# => [["A3", "a3"], ["A4", "a4"], ["Q3", "q3"], ...]
```

### Dependent make → model picker

Scope the picker to what your app serves and embed
[`Vehicles.catalog`](#the-full-ruby-api) once: the model list switches with no
request at all — **no route, no controller, no fetch.** For a one-country app,
`country:` keeps it to the models with official evidence there, in that
country's own popularity order (Spain's cars: ~140 makes, ~1,300 models, ~14 KB
of JSON; the whole worldwide car catalog is ~63 KB):

```ruby
# app/helpers/vehicles_helper.rb
PICKER = { kind: :car, country: :es }.freeze
def vehicle_catalog = Vehicles.catalog(**PICKER)
```

```erb
<div data-controller="vehicle-picker"
     data-vehicle-picker-catalog-value="<%= vehicle_catalog.to_json %>">
  <%= form.select :make,  vehicle_catalog.keys,                    { include_blank: "Make" },
        data: { vehicle_picker_target: "make", action: "change->vehicle-picker#makeChanged" } %>
  <%= form.select :model, vehicle_catalog.fetch(@car&.make.to_s, []), { include_blank: "Model" },
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
`make_options` / `model_options` and key the catalog by slug.) The same scope
also works on every list helper: `Vehicles.makes(kind: :car, country: :es)`,
`Vehicles.models("SEAT", kind: :car, country: :es)`, `make_options` /
`model_options(country:)`. Country evidence means *presence* in official data,
not an exhaustive list of what is legal there — keep an "Other" option.

### The make-model-dropdown widget, fed by your server

The [make-model-dropdown](https://github.com/vehiclesdb/make-model-dropdown)
widget (0.4.1+) does the picker for you: search, kept stored values, the
canonical id. `Vehicles.dataset_slice` takes the same scope as `catalog` and
returns the records behind the names, in the shape of the published
`dist/vehicles.json`, so the widget resolves stored values (aliases, curated
forms, former ids) and writes ids exactly as it would with the whole release.
Embed it and the page makes **no request** for vehicle data — no CDN, no API
key — and shows the release your server runs:

```ruby
# app/helpers/vehicles_helper.rb
# Built once per data release (Spain's cars: ~360 KB of JSON, ~57 KB gzipped).
def vehicles_dataset_json(**scope)
  Rails.cache.fetch(["vehicles/dataset_slice", Vehicles.data_version, scope]) do
    Vehicles.dataset_slice(**scope).to_json
  end
end
```

```erb
<script type="application/json" id="vehicles-data"><%= json_escape(vehicles_dataset_json(kind: :car, country: :es)).html_safe %></script>

<div data-controller="vehicle-picker">
  <%= form.select :make,  [@car.make].compact,  {}, data: { vehicle_picker_target: "make" } %>
  <%= form.select :model, [@car.model].compact, {}, data: { vehicle_picker_target: "model" } %>
  <%= form.hidden_field :vehiclesdb_id, data: { vehicle_picker_target: "id" } %>
</div>
```

```js
// app/javascript/controllers/vehicle_picker_controller.js
import { Controller } from "@hotwired/stimulus"
import VehiclesDropdown from "make-model-dropdown"

export default class extends Controller {
  static targets = ["make", "model", "id"]

  connect() {
    const data = JSON.parse(document.getElementById("vehicles-data").textContent)
    this.dropdown = VehiclesDropdown.attach({
      data, kind: "car", country: "es", locale: "es", values: "name",
      make: this.makeTarget, model: this.modelTarget, idInput: this.idTarget
    })
  }

  disconnect() { this.dropdown.destroy() }
}
```

Give the widget the same `kind`/`country` you sliced by. What the slice
keeps: each make's `name`, `slug`, `kinds`, `aliases`, `former_slugs`; each
model's `name`, `slug`, `kind`, `aliases`, `forms`, `former_ids`,
`global_decile`, `mass_decile`, `availability`, `country_ranks` and
`registration_years`, plus the release's `version`, `schema_version`,
`license` and `attribution`. It leaves out `regions` and `body_type`, and with
`country:` it keeps only that country in `availability` and `country_ranks`
(every record in the slice is evidenced there; the other countries are most of
the bytes). The ids are not stored: they are `kind/make-slug/model-slug`, as
everywhere. The JS and Python SDKs read a slice too (dataset mode, when it is
what they load as `dist/vehicles.json`).

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

Scope them like your picker, so a value the picker never offered (a truck, a model never seen in your market) fails too:

```ruby
validates :make,  vehicle_make:  { kind: :car, country: :es }
validates :model, vehicle_model: { make: :make, kind: :car, country: :es }   # kinds: [:car, :van] also works
```

### An "Other / not in the list" escape hatch

Make/model dropdowns should never be a dead end — the full model list is a lot, but
someone always shows up with the one car that isn't there. Turn on a first-class
"Other" option and the pieces agree by construction: `include_other:` adds it to
the picker, `allow_other:` lets it through validation.

```ruby
# config/initializers/vehicles.rb — localize the label once (default "Other")
Vehicles.configure { |c| c.other_label = "Otro" }
```

```erb
<%= form.select :make,  Vehicles.makes(include_other: true),        { include_blank: "Marca" } %>
<%= form.select :model, Vehicles.models(@car.make, include_other: true), { include_blank: "Modelo" } %>
```

```ruby
validates :make,  vehicle_make: { allow_other: true },             allow_blank: true
validates :model, vehicle_model: { make: :make, allow_other: true }, allow_blank: true
```

You store the label itself (`"Otro"`) with the name-valued helpers, or the stable
`"other"` slug with `make_options` / `model_options`. Either way `Vehicles.other?`
recognizes it on read — matching the configured label **or** the canonical slug,
case/diacritics-insensitively — so it's easy to skip a dataset lookup or hide it
from a display string:

```ruby
Vehicles.other?("Otro")     # => true   (your label)
Vehicles.other?("other")    # => true   (canonical slug, always)
Vehicles.other?("Audi")     # => false

[make, model].reject { |v| Vehicles.other?(v) }.join(" ")   # a clean display name
```

An unknown make (like the "Other" make itself) has no models, so
`Vehicles.models("Otro", include_other: true)` returns just `["Otro"]` — the
dependent picker gets a valid choice instead of an empty select.

## Recommended integration

Here's the pattern that works cleanly end to end — and a reference schema for the
columns a vehicle record actually needs.

**A record stores its vehicle's *identity*, not the reference data.** Make,
model, year, and color identify the car; `kind` and `body_type` (and, later,
specs/images) are *properties of that make+model* owned by the dataset — look
them up via the gem, don't duplicate them per row (they'd just drift). So the
schema is small and stable:

| Column          | Type      | Store                                   | Example                 |
|-----------------|-----------|-----------------------------------------|-------------------------|
| `make`          | `string`  | display name                            | `"Volkswagen"`          |
| `model`         | `string`  | display name                            | `"Golf"`                |
| `vehiclesdb_id` | `string`  | the canonical **id** (`Model#id`), nullable | `"car/volkswagen/golf"` |
| `year`          | `integer` | the year                                | `2022`                  |
| `color`         | `string`  | a canonical color **slug**              | `"blue"`                |

Everything else (`kind`, `body_type`, images, …) is derived from the id:
`Vehicles.by_id(record.vehiclesdb_id)`. No `kind`/`body_type` columns, no
migration to add new metadata later — it lands in the dataset, not your schema.

### Store the id

Names are for people; the **id** (`"car/volkswagen/golf"` — kind/make/model) is
what every VehiclesDB surface agrees on: the API, the JS/Python SDKs and the
widget take the same string, and it survives dataset releases. When a release
renames or merges a record, the new record lists the old id in `former_ids`, so a
stored id never dead-ends:

```ruby
car = Vehicles.model(params[:make], params[:model], kind: :car)
record.vehiclesdb_id = car&.id                      # nil for "Other" / unknown pairs

Vehicles.by_id("car/volkswagen/golf")               # => #<Vehicles::Model "Volkswagen Golf">
Vehicles.by_id(old_id)                              # => the record that replaced it (follow: true)
Vehicles.by_id(old_id, follow: false)               # => nil
Vehicles.live?(old_id)                              # => false
Vehicles.successor(old_id)                          # => the id to store now ("car/…/…")
```

After each data refresh, migrate stored ids in one pass:

```ruby
Car.where.not(vehiclesdb_id: nil).find_each do |car|
  now = Vehicles.successor(car.vehiclesdb_id)
  next if now.nil? || now == car.vehiclesdb_id
  model = Vehicles.by_id(now)
  car.update!(vehiclesdb_id: now, make: model.make, model: model.name)
end
```

Two records are equal when their ids are (`==`, `eql?`, `hash`): the van and the
bus of one nameplate are different records. A make that is renamed or merged
is followed too once the dataset publishes its `former_slugs`.

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

It reads what people actually type: case, accents and spacing don't matter
(`"X Ceed"` is Kia's `"XCeed"`, `"A 5"` is `"A5"`), BMW's Spanish/Italian
`"Serie 3"` is the `"3 Series"`, and a name that exists as several kinds
(Iveco's Daily: van, truck, bus) follows the [one kind rule](#matching-stored-make--model-pairs)
unless you pass `kind:` — a car-only app passes `kind: :car` everywhere.

**Year pickers.** `Model#registration_years` is a *hint* — `{ first:, last: }`, the first and last
year the nameplate shows up in official registrations, when the dataset
publishes it (nil until then) — good for ordering or pre-filling a year
`<select>`, never a validation bound (imports and late registrations fall
outside it legitimately). It is not production years: `Model#years` stays nil
until VehiclesDB publishes those.

**Only accept the kinds you support.** Filter every list/lookup by `kind:` so
the picker only ever offers vehicles your app handles — and widening later (when
new kind packs ship, or when you decide to accept them) is a one-word change, not
a migration:

```ruby
Vehicles.makes(kind: :car)                 # makes that build cars
Vehicles.models("Toyota", kind: :car)      # ...their cars only
```

No seed task, no API key — the data is bundled and read from memory. The
whole integration is the markup above plus the embedded catalog (see
[Rails dropdowns](#rails-dropdowns)).

## Country & region awareness

Vehicle availability is regional — a Vauxhall in the UK is an Opel on the continent, a Perodua exists in Malaysia and almost nowhere else. `vehicles` models this per country, from evidence:

```ruby
Vehicles.find("perodua myvi").availability      # => ["gb", "my"]
Vehicles.find("vw golf").available_in?(:nz)     # => true
Vehicles.top_models(kind: :car, country: :es)   # country-scoped popularity
```

The bundled snapshot is **global** (official registers of every covered country, across
Europe, North America, South America, Asia, Oceania and Ukraine — see [Where the data
comes from](#where-the-data-comes-from)), so the region gate accepts every
region query — `region: :eu` callers from 0.1.x keep working unchanged:

```ruby
Vehicles.makes(region: :eu)   # fine — a global snapshot covers the EU
Vehicles.region               # => :global
```

## License plates

The gem bundles the VehiclesDB **registration-mark dataset**: every plate series per jurisdiction, researched to the issuing authority's own documents — formats, eras, alphabets, designs. Ask it whether a typed registration is real:

```ruby
Vehicles.plate("12-GB-BD", jurisdiction: :nl).valid?    # => true — exact, as issued
Vehicles.plate("12gbbd", jurisdiction: :nl).suggestion  # => "12-GB-BD"  (did you mean)
Vehicles.plate("12-AB-CD", jurisdiction: :nl).strict?   # => false — vowels aren't issued
```

Matching is **two-tier**: exact as-issued first, then a separator-forgiving tier — `"1234XYZ"`, `"1234 xyz"` and `"1234-XYZ"` all resolve to the same serial, with `suggestion` giving the formatting the plate actually wears. Leniency forgives punctuation, **never the alphabet**: the strict regexes encode what the authority really issues (the Dutch vowel purge, the Spanish consonant-triplet rule…). `Match#strict?` separates validity claims from shape hits: it is true when a hit comes from a series the dataset marks `matching: strict` (the plates spec §2.7), and false for recall-only catch-alls (export plates accept any current shape, by law; Spain's 1900–1971 numeric era is one wide union). Validate user input with `strict?`.

When a plate has a series' shape but breaks its alphabet, `near_misses` names that series, so a form can say why:

```ruby
m = Vehicles.plate("1234 ABC", jurisdiction: :es)
m.valid?                                   # => false
m.near_misses.map(&:id)                    # => ["es-national-2000"]
m.jurisdiction.charset["excluded_letters"] # => ["A", "E", "I", "O", "U", "Ñ", "Q"]
```

One reason code per answer, for the error message (the hosted API answers the same codes):

```ruby
Vehicles.plate("1234 BCD", jurisdiction: :es).reason            # => :ok
Vehicles.plate("1234 ABC", jurisdiction: :es).reason            # => :excluded_letters
Vehicles.plate("1234 ABC", jurisdiction: :es).excluded_letters  # => ["A"]
Vehicles.plate("12345", jurisdiction: :es).reason               # => :bad_shape
# also :unverifiable (only a recall-only series has the shape), :empty, :unknown_jurisdiction
```

Moving people (ride sharing, rentals)? `passenger?` says whether a strictly valid
plate belongs to a series issued to passenger-carrying vehicles — a trailer
(`R-1234-BCD`) or tractor plate (`E-1234-BCD`) is valid but not that:

```ruby
Vehicles.plate("1234 BCD", jurisdiction: :es).passenger?     # => true
Vehicles.plate("R-1234-BCD", jurisdiction: :es).passenger?   # => false (reason is still :ok)
Vehicles.plates(:es).series.reject(&:passenger?).map(&:klass) # => ["agricultural", "trailer"]
```

A plate is personal data: the matcher is local, and nothing here sends it anywhere.

```ruby
Vehicles.plates              # => every jurisdiction
Vehicles.plates(:es).series  # => 19 series: formats, periods, sourced designs
```

Pilot coverage (gate L0): 🇳🇱 🇪🇸 🇩🇪 + US-Florida, 73 series, corpus-proven in NL. Same posture as everything else here: bundled, offline, forgiving in, honest out.

**Prefer HTTP?** The same matcher and the full format corpus are hosted endpoints on the [VehiclesDB API](https://vehiclesdb.com/api): `GET /api/v1/plates/{code}` (a jurisdiction's every series, with 1:1 SVG render URLs) and `GET /api/v1/plates/{code}/match?plate=…` (validity + as-issued formatting + a render of *that* registration on the real plate design). Free API keys at [vehiclesdb.com](https://vehiclesdb.com).

### Drawing a plate without sending it anywhere

A registration is personal data. To show a user their own plate on the real VehiclesDB plate art, the gem fetches a **blank template** (the series, the registration's *shape* — `NNNN LLL`, character classes only — and an optional region) and fills it **locally**:

```ruby
Vehicles::Plates.render("1234 BCD", jurisdiction: :es)
# => "<svg … aria-label=\"Spain plate 1234 BCD\">…</svg>"  (nil when it can't)

Vehicles::Plates.render("1234 BCD", jurisdiction: :es, label: "Matrícula 1234 BCD") # your language
Vehicles::Plates.render("AB-123-CD", jurisdiction: :fr, region: "75")             # FR département band
```

Only `GET {api_base_url}/plates/es/es-national-2000/template.svg?shape=NNNN_LLL` goes on the wire: no registration, no API key (the route is public). Anything ambiguous (a German `MAB1234` could be `M-AB` or `MA-B`) or unreachable answers `nil` — keep drawing whatever you drew before. Templates are cached in-process; share them across processes with any store that has `read` / `write(key, value, expires_in:)`:

```ruby
Vehicles.configure do |config|
  config.plate_template_cache = Rails.cache
  config.plate_template_ttl   = 7 * 24 * 3600 # templates are public and change only with the plate art
end
```

The pieces are public too: `Vehicles::Plates.template(code:, series:, shape:, region:)` returns the blank SVG, and `Vehicles::Plates::TemplateFill.fill(svg, registration)` is the dependency-free filler (stdlib `json` only) if you fetch templates yourself — in a browser, say.

## 🔓 More with VehiclesDB

`vehicles` is the free, open-source SDK for [**VehiclesDB**](https://vehiclesdb.com) — a hosted API for richer vehicle data. The gem is **fully standalone and always will be**; pointing it at VehiclesDB is purely additive. Drop in an API key and the same objects you already use light up with more:

```ruby
Vehicles.configure do |config|
  config.api_key = ENV["VEHICLESDB_API_KEY"]   # optional — unlocks hosted data
end

car = Vehicles.find("vw golf")

# Studio vehicle imagery — LIVE today. Mint a key at
# https://vehiclesdb.com/settings/api-keys
car.image                        # => "https://vehiclesdb.com/…/md.webp"  (640×360)
car.image(size: :lg)             # :sm 320×180 · :md 640×360 · :lg 1280×720
car.image(color: "red")          # color-accurate; unavailable colors fall back honestly
car.images(color: "red")         # the full payload: every variant + dimensions,
                                 #    available palette, served-vs-requested color
# color slugs are the gem's own canon — Vehicles.colors — so a stored
# dropdown value maps 1:1 to the studio imagery.

# Enrichment — the wired-up seam. nil today: the API does not serve these yet.
car.years                        # production years (nil until published)
car.segment                      # editorial segment (nil until published)
```

**Images in a Rails app.** Every served image is billed, so the gem caches
whole payloads (in-process by default; share them with `Rails.cache`) and never
raises. `image` answers nil on any failure; when you need to know **why**, ask
`images_result`:

```ruby
Vehicles.configure do |config|
  config.image_cache     = Rails.cache   # a hit is kept a day (capped by the payload's expiry), a 404 ten minutes
  config.on_hosted_error = ->(result) { Rails.error.report(result.to_error, handled: true) }
end

car = Vehicles.by_id(record.vehiclesdb_id)
car.image(color: record.color, exact_color: true)  # nil instead of another color's image
r = car.images_result(color: "red")
r.ok?      # => false
r.reason   # => :payment_required   (:no_api_key :not_found :unauthorized :rate_limited
           #     :invalid_request :server_error :timeout :network :color_not_available …)
r.error    # => "insufficient_credits"  (the API's own code, verbatim)
```

- `on_hosted_error` (and a warn log line) fires for a bad key, an empty wallet,
  rate limiting, server errors and timeouts — never for a plain "no image yet".
- A record a dataset release renamed answers with a 301 to its successor; the gem
  follows it (same host only, so your key never leaves it).
- `year:` is sent to the API, which answers `422 unsupported_filter` until
  year-accurate images ship (`image` → nil, `reason: :invalid_request`); until
  0.9.1 the gem silently dropped it.
- With `exact_color: true` a model's known palette is remembered, so a color it
  is not available in costs no request at all.

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
  config.use_cache = true                         # serve a refreshed dataset when it is usable
  config.cache_dir = Rails.root.join("storage", "vehicles") # a shared volume for multi-container deploys
  config.image_cache = Rails.cache                # hosted image payloads, shared across processes
end
```

## Staying current (optional)

The bundled snapshot works offline forever — but vehicle data changes (new
makes, fixes, renamed records), and you shouldn't have to ship a gem upgrade to
every app just to get them. So `vehicles` can **refresh** from the published
[dataset](https://github.com/vehiclesdb/vehiclesdb) into a file cache. Data
fixes reach your app **without a gem bump.**

`rails g vehicles:install` drops a `VehiclesRefreshJob` — schedule it (daily is
plenty), e.g. with solid_queue:

```yaml
# config/recurring.yml
vehicles_refresh:
  class: VehiclesRefreshJob
  schedule: every day at 3am
```

Or refresh by hand:

```ruby
result = Vehicles.refresh     # never raises
result.status                 # => :updated | :current | :rejected | :failed
result.message                # => "dataset 2026.11.2 → 2026.12.0"
Vehicles.refresh!             # the same, as true/false (true when updated or already current)
Vehicles.data_version         # => the version now in effect (cached, or bundled)
```

**Safe by construction.** A release is written only when all of these hold;
otherwise your current data stays untouched and `result.reason` says why:

1. The release **manifest** (a few KB, read first) announces a dataset schema
   this gem reads and a version **newer** than the newest data you already have.
   Same version → nothing is downloaded. Older → refused: never a downgrade.
2. The payload is fetched **from that exact release**, parses, carries that
   version and schema, and matches the manifest's per-kind model counts (and
   its checksum, when the manifest publishes one).
3. No kind, and no kind-in-a-country (e.g. Spain's cars), shrinks below
   `config.refresh_min_ratio` (0.9) of the data in use — a broken release can
   never empty your pickers.
4. Your own `config.refresh_guard`, if set, accepts it:
   `->(new_data, current) { … }` with two `Vehicles::Dataset`s.

It is written atomically (temp file + rename). And the file a process serves is
chosen just as carefully: a refreshed cache is used only while it is **not older
than the gem's bundled data** and in a schema the gem reads — upgrading the gem
always wins over an older download.

**Every process picks it up on its own.** Each process re-checks the file at
most every `config.reload_check_interval` seconds (default 5; one `File.stat`)
and switches to a new one — no restart, no hook. A file that is corrupt or
half-written never replaces the dataset in memory.

**Deploying web and jobs as separate containers** (Kamal, Docker Compose,
Kubernetes)? Give them one shared volume and point the gem at it, so the job's
refresh reaches the web containers:

```ruby
# config/initializers/vehicles.rb — or set VEHICLES_CACHE_DIR in both containers
Vehicles.configure { |c| c.cache_dir = Rails.root.join("storage", "vehicles") }
```

```yaml
# config/deploy.yml (Kamal): web and job already share the storage volume
volumes:
  - "myapp_storage:/rails/storage"
```

Run the refresh in ONE place (the job container); every container serves the
result. Want it fully offline/deterministic instead? `config.use_cache = false`.

## The full Ruby API

```ruby
# Lists (strings — drop straight into a form)
Vehicles.makes                          # => [String]
Vehicles.makes(kind: :car, region: :eu)
Vehicles.makes(kind: :car, country: :es) # only makes evidenced in that country
Vehicles.models("Audi")                 # => [String]
Vehicles.models("Audi", body_type: :suv)
Vehicles.models("SEAT", kind: :car, country: :es) # in Spain's popularity order

# Option pairs (for Rails `select`)
Vehicles.make_options                   # => [[label, value]]
Vehicles.model_options("Audi")          # => [[label, value]]

# Whole make => [models] map (embed once for a client-side dependent picker)
Vehicles.catalog(kind: :car)            # => { "Audi" => ["A3", ...], ... }
Vehicles.catalog(kind: :car, country: :es) # one country's picker list
Vehicles.dataset_slice(kind: :car, country: :es) # the same scope as dist/vehicles.json records (widget `data`)

# Objects
Vehicles.make("Audi")                   # => Vehicles::Make | nil
Vehicles.find("audi a3")                # => Vehicles::Model | nil  (one free-text string)
Vehicles.model("Audi", "A3")            # => Vehicles::Model | nil  (a stored make+model pair)
Vehicles.model("Iveco", "Daily", kind: :bus)  # pick a kind (default: the one kind rule)
Vehicles.model("Iveco", "Daily", kinds: [:car, :van]) # allow only some kinds
Vehicles.match_model("VW", "Tuareg")    # => Vehicles::ModelMatch | nil  (model, rung, confidence, via, candidates)
Vehicles.match_model("VW", "Golf").confident? # => true: safe to auto-apply
Vehicles.identify("vw tuareg")          # => Vehicles::ModelMatch | nil  (one free-text string)

# Canonical ids
Vehicles.by_id("car/volkswagen/golf")   # => Vehicles::Model | nil  (follows former ids)
Vehicles.by_id(id, follow: false)       # exact only
Vehicles.successor(id)                  # => the id to store now | nil
Vehicles.live?(id)                      # => true when the id names a current record
Vehicles.search("a3")                   # => [Vehicles::Model]

# Popularity & availability (open data, measured from official registers)
Vehicles.kinds                          # => [:bus, :car, :moped, :motorcycle, :truck, :van]
Vehicles.top_models(kind: :car, country: :nl, limit: 10)  # => [Vehicles::Model]

# Vehicles::Make
make.name      make.slug      make.aliases     make.kinds
make.models    make.model("a3")                make.to_h

# Vehicles::Model
model.make     model.name     model.full_name  model.slug    model.to_h
model.aliases  model.forms                     # published alternate names; curated registry spellings
model.kind     model.body_type                 model.suv?    model.coupe?   # …predicates
model.global_decile   model.popular?           # 1 = top 10% worldwide; nil-safe
model.availability    model.available_in?(:nl) model.two_wheeler?
model.id       model.former_ids                # "car/volkswagen/golf"; ids this record replaced
model.registration_years                       # { first: 1998, last: 2026 } hint, or nil (never a validation bound)
model.years    model.segment                   # production years / segment: nil until published
model.image(color:, size:, exact_color:)  model.images(color:)  model.images_result(color:)  # ← hosted API

# Colors (canonical palette)
Vehicles.colors                         # => [Vehicles::Color]
Vehicles.color("navy")                  # => Vehicles::Color | nil (forgiving)
Vehicles.color_options(locale: :es)     # => [[label, slug]]  (for select; :en default)
color.slug     color.name     color.hex     color.label(:es)
Vehicles.kind_options(locale: :es)      Vehicles.kind_label(:van, locale: :es)
Vehicles.body_type_options(locale: :es) Vehicles.body_type_label(:wagon, locale: :es)

# Plates
Vehicles.plate("1234 BCD", jurisdiction: :es)  # => Plates::Match: valid? strict? reason passenger? suggestion

# Meta
Vehicles.data_version                   # => "2026.07.0"   (version in effect: cached or bundled)
Vehicles.region                         # => :global

# Refresh (optional — keep data current without a gem upgrade)
Vehicles.refresh                        # => Vehicles::RefreshResult (status, reason, message); never raises
Vehicles.refresh!                       # the same as true/false
Vehicles.reload!                        # drop the in-memory dataset now (processes also re-check on their own)
```

## Where the data comes from

The bundled dataset is [**VehiclesDB**](https://github.com/vehiclesdb/vehiclesdb) — an open dataset **reconciled from the official vehicle registers of every covered country, on five continents** (the Dutch RDW, UK DfT, Spanish DGT, Finnish Traficom, German KBA, US EPA, New Zealand's Motor Vehicle Register, Thailand's DLT, Ukraine's MVS, and more — the exact list for the bundled 2026.11.9 snapshot is `countries` in the data repo's `manifest.json`). A model ships only when **two independent official sources corroborate it** — or one shows a registration count no typo could produce — so you get real nameplates without the registry noise.

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
- **This dataset** (`data/vehicles.json`): **CC-BY 4.0**. Visible credit with a link is a condition of the license (§3(a)). The form we request: *"Vehicle data by [VehiclesDB](https://vehiclesdb.com)"* — on websites, a followable link (deep links to the make/model page you used are even better); in apps, name us in an about/credits screen. Ready-made snippets (HTML, Markdown, BibTeX, badge): [vehiclesdb.com/attribution](https://vehiclesdb.com/attribution). Prefer not to credit, or need the enriched paid layer? [Commercial license](https://vehiclesdb.com) — it waives only OUR credit, never the upstream register notices.
- **The gem code:** MIT.

The data is versioned (`Vehicles.data_version`). Each gem release bundles a known snapshot — the offline, deterministic floor. To get newer data, either upgrade the gem or enable [refresh](#staying-current-optional) (which pulls published releases without a gem bump). Either way it's explicit and versioned — no silent mutations.

## How it works

No magic, just good defaults:

- **Bundled, not fetched.** `data/vehicles.json` is packaged in the gem and loaded into a frozen, memoized in-memory index on first access. First call builds the index; every call after is a hash lookup. No HTTP, no SQLite, no ActiveRecord on the read path.
- **Zero-config.** No initializer required. No migration. Nothing to schedule.
- **Standalone first, SDK second.** The hosted VehiclesDB layer is strictly optional and detected at runtime; the gem never hard-depends on it.
- **Rails-aware, not Rails-bound.** Form helpers and validators register through a lightweight Railtie only when Rails is loaded.

## Roadmap

Bundled today: the full VehiclesDB catalog across all 6 kinds, with popularity +
availability, plus the MCP server (the live counts are in the data repo's
`manifest.json`; this README deliberately carries none). On the way:

- 🌍 More **countries** (the dataset grows monthly)
- 📅 Production **years** in the local data
- 🧬 **Generations & variants** layers (the schema already reserves them)
- 🏷️ **Segments** (supercar, city car, hot hatch) and richer metadata

Want one of these sooner? Open an issue.

## Testing

Run the test suite with `bundle exec rake test`. The gem is tested against multiple Rails versions with Appraisal: `bundle exec appraisal rails-8.0 rake test`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/vehiclesdb/vehicles. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). The bundled dataset is licensed CC-BY 4.0 (see [Where the data comes from](#where-the-data-comes-from)).
