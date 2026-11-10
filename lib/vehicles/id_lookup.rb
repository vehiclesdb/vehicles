# frozen_string_literal: true

module Vehicles
  # Canonical-id lookups, extended onto Vehicles (`Vehicles.by_id`, …). An id
  # is "kind/make-slug/model-slug" (Model#id, RESOLUTION.md §1): the thing to
  # store. Datasets rename and merge records append-only, listing the old id
  # in the successor's `former_ids`, so a stored id never dead-ends.
  module IdLookup
    # The Model a canonical id names, or nil. With `follow: true` (the
    # default) a RETIRED id answers its successor: the record that lists it in
    # `former_ids`, or — once the dataset publishes make `former_slugs` — the
    # same model under the make's new slug. An id two different records
    # absorbed (a split) answers nil: there is no one successor.
    #   Vehicles.by_id("car/volkswagen/golf")              # => #<Vehicles::Model "Volkswagen Golf" hatchback>
    #   Vehicles.by_id("car/alfa-romeo/159sw")              # => the 159 (renamed record)
    #   Vehicles.by_id("car/alfa-romeo/159sw", follow: false) # => nil
    #   Vehicles.by_id(id, kinds: [:car])  # nil unless the answer is a car
    def by_id(id, follow: true, kinds: nil)
      id = id.to_s.strip
      found = dataset.models_by_id(id).first || (follow ? dataset.successor_of(id) : nil)
      found && KindRule.allows?(KindRule.symbols(kinds), found) ? found : nil
    end

    # The id to store NOW for a stored id: itself when live, its successor's
    # id when retired, nil when the dataset does not know it. Run it over a
    # column after each refresh to migrate renamed ids.
    #   Vehicles.successor("car/alfa-romeo/159sw")  # => "car/alfa-romeo/159"
    def successor(id)
      by_id(id, follow: true)&.id
    end

    # Does this id name a current record (not a retired one)?
    def live?(id)
      !dataset.models_by_id(id.to_s.strip).empty?
    end
  end
end
