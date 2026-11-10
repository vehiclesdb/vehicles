# frozen_string_literal: true

module Vehicles
  # The canonical color palette — the ~handful of colors that cover virtually
  # every car on the road, plus an explicit `other` catch-all. Ordered roughly by
  # real-world frequency (white/black/grey lead the global fleet) so a dropdown
  # reads sensibly. Slugs are the stable keys you store; names are English labels
  # to localize; hexes are representative swatches.
  module Colors
    ALL = [
      Color.new("white",  "White",  "#F4F4F4"),
      Color.new("black",  "Black",  "#1B1B1B"),
      Color.new("grey",   "Grey",   "#8A8D90"),
      Color.new("silver", "Silver", "#C7CCD1"),
      Color.new("blue",   "Blue",   "#27408B"),
      Color.new("red",    "Red",    "#B81D24"),
      Color.new("green",  "Green",  "#2E6B3E"),
      Color.new("brown",  "Brown",  "#5A3A22"),
      Color.new("beige",  "Beige",  "#D9C6A5"),
      Color.new("orange", "Orange", "#E8731A"),
      Color.new("yellow", "Yellow", "#F2C200"),
      Color.new("gold",   "Gold",   "#C8A951"),
      Color.new("purple", "Purple", "#6B3FA0"),
      Color.new("other",  "Other",  "#9AA0A6")
    ].freeze

    # English spellings/synonyms (normalized keys → canonical slug). Every
    # locale's synonyms live in Labels::COLOR_SYNONYMS.
    SYNONYMS = Labels::COLOR_SYNONYMS[:en]

    BY_SLUG = ALL.to_h { |c| [c.slug, c] }.freeze
    BY_NAME = ALL.to_h { |c| [Vehicles.normalize(c.name), c] }.freeze

    # Every normalized label and synonym in every locale → Color, so "Rojo",
    # "gris", "marrón", "plateada" and "navy" all resolve (Vehicles.color).
    LOOKUP = begin
      table = {}
      Labels::LOCALES.each do |locale|
        Labels::COLORS[locale].each { |slug, label| table[Vehicles.normalize(label)] ||= BY_SLUG[slug] }
        Labels::COLOR_SYNONYMS[locale].each { |key, slug| table[Vehicles.normalize(key)] ||= BY_SLUG[slug] }
      end
      table.freeze
    end
  end
end
