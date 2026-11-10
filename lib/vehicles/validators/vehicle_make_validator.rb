# frozen_string_literal: true

# Drop-in validator: `validates :make, vehicle_make: true`.
#
# Rails resolves the `vehicle_make:` key to this top-level constant automatically
# (camelize + "Validator"), so no registration is needed — requiring the file is
# enough. Forgiving (aliases/case/slug) like every other lookup, and defensive:
# blank values pass (pair with `presence: true` if you want them rejected), and
# any internal error degrades to a generic message instead of blowing up a form.
#
# Pass `allow_other: true` to accept the "Other / not in the list" escape hatch
# (see `Vehicles.other?`) — pair it with `Vehicles.make_options(include_other:)`
# so the dropdown and the validation agree by construction.
#
# Scope it like your picker (0.9.2) so a value the picker never offered fails:
#   validates :make, vehicle_make: { kind: :car, country: :es }
# `kind:` — the make builds that kind; `country:` — it has a model (of that
# kind) with evidence in that country. Country evidence is presence, not
# exhaustive eligibility: opt in only when the picker uses the same scope.
class VehicleMakeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    return if options[:allow_other] && Vehicles.other?(value)

    # Exact-only: a typo must fail validation, not be stored as if it were the
    # make it resembles (Vehicles.make is typo-tolerant since 0.7.8).
    make = Vehicles.make(value, fuzzy: false)
    return if make && in_scope?(make)

    record.errors.add(attribute, options[:message] || "is not a recognized vehicle make")
  rescue StandardError => e
    Vehicles.logger&.error("[vehicles] vehicle_make validation error: #{e.message}")
    record.errors.add(attribute, options[:message] || "is not a recognized vehicle make")
  end

  private

  def in_scope?(make)
    kind = options[:kind]
    return false if kind && !make.kinds.include?(kind.to_sym)

    options[:country].nil? || make.available_in?(options[:country], kind: kind)
  end
end
