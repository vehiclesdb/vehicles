# frozen_string_literal: true

require "test_helper"

module Vehicles
  class ProvidersTest < TestCase
    def test_local_provider_always_available
      assert_predicate Providers::LocalProvider, :available?
    end

    def test_hosted_provider_unavailable_without_api_key
      refute_predicate Providers::HostedProvider, :available?
    end

    def test_hosted_provider_available_with_api_key
      Vehicles.configure { |c| c.api_key = "secret" }

      assert_predicate Providers::HostedProvider, :available?
    end

    def test_provider_order_prefers_hosted
      assert_equal [Providers::HostedProvider, Providers::LocalProvider], Vehicles.providers
    end

    def test_hosted_enrichment_when_key_present
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns(
        "year_start" => 1974, "year_end" => 2024,
        "segment" => "hot_hatch", "url" => "https://cdn.vehiclesdb.com/vw/golf.webp"
      )

      golf = Vehicles.find("vw golf")

      assert_equal(1974..2024, golf.years)
      assert_equal :hot_hatch, golf.segment
      assert_equal "https://cdn.vehiclesdb.com/vw/golf.webp", golf.image(year: 2020)
    end

    def test_open_ended_year_range
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns("year_start" => 2019, "year_end" => nil)

      assert_equal(2019..nil, Vehicles.find("vw golf").years)
    end

    def test_hosted_failure_degrades_to_nil
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns(nil) # API down / 404 / bad JSON

      assert_nil Vehicles.find("vw golf").years
      assert_nil Vehicles.find("vw golf").image
    end

    def test_resolve_never_raises_even_if_a_provider_explodes
      skip "mocha not available" unless defined?(Mocha)

      exploding = Object.new
      def exploding.available? = true
      def exploding.years(*) = raise("boom")

      Vehicles.stubs(:providers).returns([exploding, Providers::LocalProvider])

      assert_nil Vehicles.find("vw golf").years # logged + swallowed, falls through
    end
  end
end
