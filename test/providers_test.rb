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
        "year_start" => 1974, "year_end" => 2024, "segment" => "hot_hatch"
      )

      golf = Vehicles.find("vw golf")

      assert_equal(1974..2024, golf.years)
      assert_equal :hot_hatch, golf.segment
    end

    def test_open_ended_year_range
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns("year_start" => 2019, "year_end" => nil)

      assert_equal(2019..nil, Vehicles.find("vw golf").years)
    end

    def test_image_hits_the_live_images_endpoint_and_returns_the_variant_url
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      golf = Vehicles.find("vw golf")
      Providers::HostedProvider
        .expects(:get)
        .with("/v1/vehicles/#{golf.kind}/#{golf.make_slug}/#{golf.model_slug}/images", { color: "blue" })
        .returns(images_payload)

      assert_equal "https://vehiclesdb.com/img/md.webp", golf.image(color: "blue")
    end

    def test_image_size_selects_the_variant
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns(images_payload)

      assert_equal "https://vehiclesdb.com/img/sm.webp", Vehicles.find("vw golf").image(size: :sm)
    end

    def test_image_never_sends_the_reserved_year_filter
      skip "mocha not available" unless defined?(Mocha)

      # The live API 422s on `year`/`trim` (reserved by contract). The provider
      # must serve the current rendering instead of tripping that guard.
      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.expects(:get).with(anything, {}).returns(images_payload)

      refute_nil Vehicles.find("vw golf").image(year: 2020)
    end

    def test_images_returns_the_full_payload
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:get).returns(images_payload)

      payload = Vehicles.find("vw golf").images(color: "blue")

      assert_equal %w[blue grey], payload["palette"]
      assert_equal 640, payload.dig("variants", "md", "width")
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

    private

    # A live-contract images response (vehiclesdb.com API, PRD-IMAGES §3).
    def images_payload
      {
        "id" => "car/volkswagen/golf", "color" => "blue", "requested_color" => "blue",
        "palette" => %w[blue grey],
        "variants" => {
          "sm" => { "url" => "https://vehiclesdb.com/img/sm.webp", "width" => 320, "height" => 180 },
          "md" => { "url" => "https://vehiclesdb.com/img/md.webp", "width" => 640, "height" => 360 },
          "lg" => { "url" => "https://vehiclesdb.com/img/lg.webp", "width" => 1280, "height" => 720 }
        }
      }
    end
  end
end
