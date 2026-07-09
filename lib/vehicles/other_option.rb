# frozen_string_literal: true

module Vehicles
  # The "Other / not in the list" escape hatch for make/model pickers. Mixed into
  # the Vehicles singleton (`extend OtherOption` in vehicles.rb) so `Vehicles.other?`
  # and `Vehicles.other_label` read as first-class module methods, and the
  # `include_other:` helpers (`makes`/`models`/`*_options`) can append it. Pair with
  # `allow_other: true` on the vehicle_make/vehicle_model validators. See the README
  # "An Other / not in the list escape hatch" section.
  module OtherOption
    # Stable, language-independent value for the escape hatch — the slug the
    # `*_options(include_other:)` helpers emit, and a value `other?` always
    # recognizes regardless of the configured display label.
    OTHER_SLUG = "other"

    # The configured "Other" display label (default "Other"). Use it as the
    # picker's escape-hatch value and to recognize it on read.
    def other_label
      configuration.other_label
    end

    # Is `value` the "Other / not in the list" escape hatch? Forgiving: matches the
    # configured label ("Otro") OR the canonical slug ("other"), case/diacritics-
    # insensitively. nil/blank => false. Handy for hiding it from a display string
    # or skipping dataset lookups on it.
    def other?(value)
      normalized = normalize(value)
      return false if normalized.empty?

      normalized == OTHER_SLUG || normalized == normalize(other_label)
    end

    private

    # Append the "Other" label to a name list (makes/models), unless disabled or
    # already present. Kept idempotent so a dataset that ever ships its own
    # "Other" entry won't double it.
    def append_other_name(names, include_other)
      return names unless include_other
      return names if names.any? { |name| other?(name) }

      names + [other_label]
    end

    # Same, for [[label, value], ...] option pairs — the appended value is the
    # stable OTHER_SLUG so slug-valued forms store a language-independent value.
    def append_other_option(pairs, include_other)
      return pairs unless include_other
      return pairs if pairs.any? { |(_label, value)| other?(value) }

      pairs + [[other_label, OTHER_SLUG]]
    end
  end
end
