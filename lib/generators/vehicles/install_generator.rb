# frozen_string_literal: true

require "rails/generators/base"

module Vehicles
  module Generators
    # `rails generate vehicles:install`
    #
    # Writes a configuration initializer. That's it — there is deliberately NO
    # migration: `vehicles` ships its dataset bundled in the gem and reads it from
    # memory, so there is no table to create and nothing to seed. The gem already
    # works the moment it's in your Gemfile; this generator just gives you a place
    # to set a region or plug in a VehiclesDB API key.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/vehicles.rb"
      end

      def display_post_install_message
        say "\n🚗 vehicles installed!", :green
        say "\nNo migration needed — the dataset ships inside the gem and just works."
        say "\nTry it now:"
        say "  Vehicles.makes                 # => [\"Alfa Romeo\", \"Audi\", ...]", :cyan
        say "  Vehicles.models(\"VW\")          # => [\"Golf\", \"Polo\", ...]", :cyan
        say "  Vehicles.make_options          # => [[\"Audi\", \"audi\"], ...]  (for select)", :cyan
        say "\nConfig (optional) lives in config/initializers/vehicles.rb."
        say "Add a VehiclesDB API key there to unlock years, images, and segments.\n"
      end
    end
  end
end
