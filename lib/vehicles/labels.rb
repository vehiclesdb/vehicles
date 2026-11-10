# frozen_string_literal: true

module Vehicles
  # Display labels for the gem's closed vocabularies — colors, kinds, body
  # types — in English and Spanish, so an app does not hand-maintain the same
  # tables. Model and make NAMES are never translated: they are proper nouns
  # (real-world spellings such as "Clase A" arrive as curated `forms`).
  #
  #   Vehicles.color_options(locale: :es)   # => [["Blanco", "white"], ...]
  #   Vehicles.color("rojo")                # => #<Vehicles::Color red ...>
  #   Vehicles.kind_label(:van, locale: :es) # => "Furgoneta"
  #   Vehicles.kind_options(locale: :es)     # => [["Autobús", "bus"], ["Coche", "car"], ...]
  #   Vehicles.body_type_label(:wagon, locale: :es) # => "Familiar"
  #
  # Locales: :en, :es ("es-MX", :es_ES … fold to :es). Anything else falls
  # back to English, never raises. You store the slug; the label is display.
  module Labels
    LOCALES = %i[en es].freeze

    COLORS = {
      en: { "white" => "White", "black" => "Black", "grey" => "Grey", "silver" => "Silver", "blue" => "Blue",
            "red" => "Red", "green" => "Green", "brown" => "Brown", "beige" => "Beige", "orange" => "Orange",
            "yellow" => "Yellow", "gold" => "Gold", "purple" => "Purple", "other" => "Other" },
      es: { "white" => "Blanco", "black" => "Negro", "grey" => "Gris", "silver" => "Plata", "blue" => "Azul",
            "red" => "Rojo", "green" => "Verde", "brown" => "Marrón", "beige" => "Beige", "orange" => "Naranja",
            "yellow" => "Amarillo", "gold" => "Dorado", "purple" => "Morado", "other" => "Otro" }
    }.freeze

    # What people type for a color besides its label, per locale: feminine
    # forms ("furgoneta blanca"), the adjective forms of the metals and
    # everyday near-synonyms. Matched after Vehicles.normalize ("marrón" →
    # "marron"), so accents never matter.
    COLOR_SYNONYMS = {
      en: { "gray" => "grey", "silvery" => "silver", "tan" => "beige", "cream" => "beige",
            "burgundy" => "red", "navy" => "blue", "violet" => "purple", "golden" => "gold" },
      es: { "blanca" => "white", "negra" => "black", "roja" => "red", "amarilla" => "yellow",
            "dorada" => "gold", "morada" => "purple", "plateado" => "silver", "plateada" => "silver",
            "plata metalizado" => "silver", "granate" => "red", "burdeos" => "red", "azul marino" => "blue",
            "violeta" => "purple", "lila" => "purple", "crema" => "beige", "otra" => "other",
            "gris plata" => "silver", "marron" => "brown", "cafe" => "brown" }
    }.freeze

    KINDS = {
      en: { "car" => "Car", "motorcycle" => "Motorcycle", "moped" => "Moped", "van" => "Van",
            "truck" => "Truck", "bus" => "Bus", "pickup" => "Pickup", "trailer" => "Trailer",
            "quad" => "Quad", "trike" => "Trike" },
      es: { "car" => "Coche", "motorcycle" => "Moto", "moped" => "Ciclomotor", "van" => "Furgoneta",
            "truck" => "Camión", "bus" => "Autobús", "pickup" => "Pick-up", "trailer" => "Remolque",
            "quad" => "Quad", "trike" => "Triciclo" }
    }.freeze

    BODY_TYPES = {
      en: { "hatchback" => "Hatchback", "sedan" => "Sedan", "wagon" => "Estate", "suv" => "SUV",
            "mpv" => "MPV", "coupe" => "Coupé", "convertible" => "Convertible", "roadster" => "Roadster",
            "pickup" => "Pickup", "van" => "Van" },
      es: { "hatchback" => "Hatchback", "sedan" => "Sedán", "wagon" => "Familiar", "suv" => "SUV",
            "mpv" => "Monovolumen", "coupe" => "Coupé", "convertible" => "Descapotable",
            "roadster" => "Roadster", "pickup" => "Pick-up", "van" => "Furgoneta" }
    }.freeze

    module_function

    # :en/:es from anything ("es-MX", :es_ES, "ES"); English otherwise.
    def locale(value)
      base = value.to_s.downcase[/\A[a-z]+/]&.to_sym
      LOCALES.include?(base) ? base : :en
    end

    def color(slug, locale = :en) = lookup(COLORS, slug, locale)
    def kind(kind, locale = :en) = lookup(KINDS, kind, locale)
    def body_type(type, locale = :en) = lookup(BODY_TYPES, type, locale)

    # The table entry in that locale, else English, else nil.
    def lookup(table, key, locale)
      key = key.to_s
      table[locale(locale)][key] || table[:en][key]
    end
  end

  # The palette and label helpers extended onto Vehicles
  # (`Vehicles.colors`, `Vehicles.color`, `Vehicles.kind_label`, …).
  module LabelOptions
    # The canonical color palette, frequency-ordered. => [Vehicles::Color, ...]
    def colors
      Colors::ALL
    end

    # [[label, slug], ...] for a Rails `select`, in palette order. The slug
    # is the stable value you store; the label is in `locale` (:en default,
    # :es; anything else falls back to English).
    #   Vehicles.color_options(locale: :es)  # => [["Blanco", "white"], ["Negro", "black"], ...]
    def color_options(locale: :en)
      Colors::ALL.map { |c| [c.label(locale), c.slug] }
    end

    # Resolve a color by slug, or by name in any supported language
    # (forgiving: case, diacritics, synonyms — "gray"→grey, "navy"→blue,
    # "Rojo"→red, "marrón"→brown, "plateada"→silver). A Vehicles::Color, or nil.
    def color(query)
      q = normalize(query)
      return nil if q.empty?

      Colors::BY_SLUG[q] || Colors::LOOKUP[q]
    end

    # "Furgoneta" for (:van, locale: :es); English for unknown locales; nil
    # for an unknown kind.
    def kind_label(kind, locale: :en)
      Labels.kind(kind, locale)
    end

    # [[label, kind], ...] for a kind <select>, sorted by label. Defaults to
    # the kinds the dataset publishes.
    #   Vehicles.kind_options(locale: :es)  # => [["Autobús", "bus"], ["Camión", "truck"], ...]
    def kind_options(locale: :en, kinds: self.kinds)
      kinds.map { |k| [kind_label(k, locale: locale) || k.to_s, k.to_s] }.sort_by { |label, _| normalize(label) }
    end

    # "Familiar" for (:wagon, locale: :es); nil for an unknown body type.
    def body_type_label(body_type, locale: :en)
      Labels.body_type(body_type, locale)
    end

    # [[label, body_type], ...] in Model::BODY_TYPES order.
    def body_type_options(locale: :en)
      Model::BODY_TYPES.map { |t| [body_type_label(t, locale: locale), t.to_s] }
    end
  end
end
