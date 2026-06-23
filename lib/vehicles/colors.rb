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

    # Accept a few common spellings/synonyms so lookups are forgiving like the
    # rest of the gem (normalized keys → canonical slug).
    SYNONYMS = {
      "gray"     => "grey",
      "silvery"  => "silver",
      "tan"      => "beige",
      "cream"    => "beige",
      "burgundy" => "red",
      "navy"     => "blue"
    }.freeze

    BY_SLUG = ALL.each_with_object({}) { |c, h| h[c.slug] = c }.freeze
    BY_NAME = ALL.each_with_object({}) { |c, h| h[Vehicles.normalize(c.name)] = c }.freeze
  end
end
