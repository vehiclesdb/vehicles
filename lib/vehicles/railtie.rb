# frozen_string_literal: true

require "rails/railtie"

module Vehicles
  # Wires the gem into Rails without forcing anything: it only registers the
  # ActiveModel validators, and only once ActiveRecord/ActiveModel is loaded.
  # There's no engine, no migration, no table — the data lives in the bundled
  # JSON, so there's nothing to install.
  class Railtie < ::Rails::Railtie
    initializer "vehicles.validators" do
      ActiveSupport.on_load(:active_record) { Vehicles.load_validators! }
      # Also cover plain-ActiveModel hosts (e.g. a Tableless model) loaded early.
      Vehicles.load_validators! if defined?(ActiveModel::EachValidator)
    end
  end
end
