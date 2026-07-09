# frozen_string_literal: true

# Drop-in validator: `validates :model, vehicle_model: { make: :make }`.
#
# Checks that the value is a real model OF the make held in another attribute.
# Pass `make:` pointing at the attribute that holds the make (defaults to :make).
#
#   validates :model, vehicle_model: { make: :car_make }
#
# Defensive by design: blank model passes; an unknown/blank make can't disprove
# the model, so it passes (let the make's own validator flag that); errors never
# raise out of a form submission.
#
# Pass `allow_other: true` to accept the "Other / not in the list" escape hatch
# (see `Vehicles.other?`) — pair it with `Vehicles.model_options(include_other:)`.
class VehicleModelValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    return if options[:allow_other] && Vehicles.other?(value)

    make_attribute = options[:make] || :make
    make_value = record.respond_to?(make_attribute) ? record.public_send(make_attribute) : nil
    make = Vehicles.make(make_value)
    return if make.nil? # unknown make -> defer to the make validator
    return if make.model(value)

    record.errors.add(attribute, options[:message] || "is not a recognized #{make.name} model")
  rescue StandardError => e
    Vehicles.logger&.error("[vehicles] vehicle_model validation error: #{e.message}")
    record.errors.add(attribute, options[:message] || "is not a recognized vehicle model")
  end
end
