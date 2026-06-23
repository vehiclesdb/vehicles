# frozen_string_literal: true

# SimpleCov must start before any application code is required, so it goes first.
begin
  require "simplecov"
rescue LoadError
  # Coverage is optional locally.
end

require "minitest/autorun"

# ActiveModel is only needed for the validator tests; load it if present so the
# rest of the suite still runs in a plain-Ruby environment.
begin
  require "active_model"
rescue LoadError
  # validator tests will skip
end

begin
  require "mocha/minitest"
rescue LoadError
  # provider stub tests will skip
end

require "vehicles"
Vehicles.load_validators!

module Vehicles
  # Base test case: resets configuration + provider caches between tests so state
  # never leaks (aliases, api_key, the hosted provider's memoized cache).
  class TestCase < Minitest::Test
    def teardown
      Vehicles.reset_configuration!
      super
    end

    # Convenience: the whole dataset, flattened, for integrity-style assertions.
    def all_models
      Vehicles.makes.flat_map { |mk| Vehicles.make(mk).models }
    end
  end
end
