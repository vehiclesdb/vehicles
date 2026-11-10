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

    def test_years_and_segment_never_reach_the_network
      skip "mocha not available" unless defined?(Mocha)

      # The API serves no years/segment endpoint yet: asking must not spend a
      # request on one — the chain falls through to the local data.
      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.expects(:fetch).never

      golf = Vehicles.find("vw golf")

      assert_nil golf.years
      assert_nil golf.segment
    end

    def test_image_hits_the_live_images_endpoint_and_returns_the_variant_url
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      golf = Vehicles.find("vw golf")
      Providers::HostedProvider
        .expects(:fetch)
        .with("/api/v1/vehicles/car/volkswagen/golf/images", { color: "blue" })
        .returns(ok(images_payload))

      assert_equal "https://vehiclesdb.com/img/md.webp", golf.image(color: "blue")
    end

    def test_image_size_selects_the_variant
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:fetch).returns(ok(images_payload))

      assert_equal "https://vehiclesdb.com/img/sm.webp", Vehicles.find("vw golf").image(size: :sm)
    end

    # Until 0.9.1 `year:` was accepted and silently dropped. It is sent now:
    # the API answers 422 unsupported_filter until year-accurate renders
    # ship, and the result says so instead of serving a year it never checked.
    def test_image_sends_year_and_reports_the_api_refusal
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      refused = HostedResult.from_status(422, body_error: "unsupported_filter", path: "/x")
      Providers::HostedProvider.expects(:fetch).twice.with(anything, { year: "2020" }).returns(refused)
      golf = Vehicles.find("vw golf")

      assert_nil golf.image(year: 2020)
      result = golf.images_result(year: 2020) # a 422 is never cached: asked again

      assert_equal [:invalid_request, "unsupported_filter"], [result.reason, result.error]
    end

    def test_images_returns_the_full_payload
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:fetch).returns(ok(images_payload))

      payload = Vehicles.find("vw golf").images(color: "blue")

      assert_equal %w[blue grey], payload["palette"]
      assert_equal 640, payload.dig("variants", "md", "width")
    end

    def test_hosted_failure_degrades_to_nil
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.stubs(:fetch).returns(HostedResult.new(reason: :network))

      assert_nil Vehicles.find("vw golf").years
      assert_nil Vehicles.find("vw golf").image
    end

    def test_no_key_is_a_reason_not_a_request
      result = Vehicles.find("vw golf").images_result

      assert_equal :no_api_key, result.reason
      refute_predicate result, :ok?
    end

    def test_a_hit_is_cached_so_the_second_view_costs_nothing
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      Providers::HostedProvider.expects(:fetch).once.returns(ok(images_payload))
      golf = Vehicles.find("vw golf")

      assert_equal "https://vehiclesdb.com/img/md.webp", golf.image(color: "blue")
      assert_equal "https://vehiclesdb.com/img/lg.webp", golf.image(color: "blue", size: :lg)
      assert_predicate golf.images_result(color: "blue"), :cached?
    end

    def test_errors_are_never_cached_and_reach_the_callback
      skip "mocha not available" unless defined?(Mocha)

      seen = []
      Vehicles.configure do |c|
        c.api_key = "secret"
        c.on_hosted_error = ->(r) { seen << [r.reason, r.error] }
      end
      broke = HostedResult.from_status(402, body_error: "insufficient_credits", path: "/x")
      Providers::HostedProvider.expects(:fetch).twice.returns(broke)
      golf = Vehicles.find("vw golf")

      assert_nil golf.image
      assert_nil golf.image

      assert_equal [[:payment_required, "insufficient_credits"]] * 2, seen
    end

    def test_a_missing_render_is_not_an_alert
      skip "mocha not available" unless defined?(Mocha)

      seen = []
      Vehicles.configure do |c|
        c.api_key = "secret"
        c.on_hosted_error = ->(r) { seen << r }
      end
      Providers::HostedProvider.expects(:fetch).once
                               .returns(HostedResult.from_status(404, body_error: "no_image", path: "/x"))
      golf = Vehicles.find("vw golf")

      assert_equal :not_found, golf.images_result.reason
      assert_predicate golf.images_result, :cached? # a definitive miss is remembered briefly
      assert_empty seen
    end

    def test_a_raising_callback_never_breaks_the_page
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure do |c|
        c.api_key = "secret"
        c.on_hosted_error = ->(_r) { raise "tracker down" }
      end
      Providers::HostedProvider.stubs(:fetch).returns(HostedResult.new(reason: :timeout))

      assert_nil Vehicles.find("vw golf").image
    end

    def test_exact_color_refuses_the_fallback_and_remembers_the_palette
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure { |c| c.api_key = "secret" }
      grey = images_payload.merge("color" => "grey", "requested_color" => "red")
      Providers::HostedProvider.expects(:fetch).once.returns(ok(grey))
      golf = Vehicles.find("vw golf")

      assert_equal :color_not_rendered, golf.images_result(color: "red", exact_color: true).reason
      assert_nil golf.image(color: "red", exact_color: true) # from cache
      # The palette (blue, grey) is known now: no call for a color outside it.
      assert_equal :color_not_rendered, golf.images_result(color: "green", exact_color: true).reason
      refute_nil golf.image(color: "red") # without exact_color the fallback is served
    end

    def test_the_cache_ttl_is_capped_by_expires_at
      soon = (Time.now + 7200).utc.iso8601

      assert_operator Providers::HostedProvider.hit_ttl(images_payload.merge("expires_at" => soon)), :<=, 3600
      assert_equal 86_400, Providers::HostedProvider.hit_ttl(images_payload)
    end

    def test_image_cache_false_disables_caching
      skip "mocha not available" unless defined?(Mocha)

      Vehicles.configure do |c|
        c.api_key = "secret"
        c.image_cache = false
      end
      Providers::HostedProvider.expects(:fetch).twice.returns(ok(images_payload))
      golf = Vehicles.find("vw golf")
      2.times { golf.image }
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

    def ok(payload) = HostedResult.new(reason: :ok, status: 200, payload: payload)

    # A live-contract images response (vehiclesdb.com API).
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
