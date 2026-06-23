# frozen_string_literal: true

# Drop-in validator: `validates :make, vehicle_make: true`.
#
# Rails resolves the `vehicle_make:` key to this top-level constant automatically
# (camelize + "Validator"), so no registration is needed — requiring the file is
# enough. Forgiving (aliases/case/slug) like every other lookup, and defensive:
# blank values pass (pair with `presence: true` if you want them rejected), and
# any internal error degrades to a generic message instead of blowing up a form.
class VehicleMakeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    return if Vehicles.make(value)

    record.errors.add(attribute, options[:message] || "is not a recognized vehicle make")
  rescue StandardError => e
    Vehicles.logger&.error("[vehicles] vehicle_make validation error: #{e.message}")
    record.errors.add(attribute, options[:message] || "is not a recognized vehicle make")
  end
end
