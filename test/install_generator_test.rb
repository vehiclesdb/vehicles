# frozen_string_literal: true

require "test_helper"

# The install generator needs full Rails (rails/generators). The base bundle is
# ActiveModel-only, so this runs under the Appraisal gemfiles (rails-7.2 / 8.0)
# and skips otherwise.
begin
  require "rails/generators"
  require "rails/generators/test_case"
  require "generators/vehicles/install_generator"
rescue LoadError
  # no full Rails in this bundle
end

if defined?(Rails::Generators::TestCase)
  module Vehicles
    class InstallGeneratorTest < Rails::Generators::TestCase
      tests Vehicles::Generators::InstallGenerator
      destination File.expand_path("../tmp/generator", __dir__)
      setup :prepare_destination

      def test_creates_a_configuration_initializer_and_no_migration
        run_generator

        assert_file "config/initializers/vehicles.rb" do |content|
          assert_match(/Vehicles\.configure/, content)
          assert_match(/config\.region/, content)
          assert_match(/config\.api_key/, content)
        end
        # The gem has no table — the generator must NOT create a migration.
        assert_no_migration "db/migrate/create_vehicles_tables.rb"
      end
    end
  end
end
