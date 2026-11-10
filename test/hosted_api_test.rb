# frozen_string_literal: true

require "test_helper"
require "socket"

module Vehicles
  # The hosted provider over a REAL socket: what goes on the wire (the exact
  # request line, the auth header) and what comes back when the API is not
  # there. No stubs — a one-shot local HTTP server plays the API.
  class HostedApiTest < TestCase
    def setup
      @server = TCPServer.new("127.0.0.1", 0)
      Vehicles.configure do |c|
        c.api_key = "secret"
        c.api_base_url = "http://127.0.0.1:#{@server.addr[1]}"
      end
      @leon = Vehicles.model("SEAT", "Leon")
    end

    def teardown
      @server.close unless @server.closed?
      super
    end

    def test_images_requests_the_api_v1_path
      request = serve(200, IMAGES_JSON) { @leon.images(color: "white") }

      assert_equal "GET /api/v1/vehicles/car/seat/leon/images?color=white HTTP/1.1", request[:line]
    end

    def test_images_sends_the_key_as_a_bearer_token
      request = serve(200, IMAGES_JSON) { @leon.images }

      assert_equal "GET /api/v1/vehicles/car/seat/leon/images HTTP/1.1", request[:line]
      assert_equal "Bearer secret", request[:headers]["authorization"]
      assert_equal "application/json", request[:headers]["accept"]
    end

    def test_image_returns_the_variant_url_from_the_wire
      url = nil
      serve(200, IMAGES_JSON) { url = @leon.image(color: "white", size: :lg) }

      assert_equal "https://cdn.example/leon-white-lg.webp", url
    end

    def test_a_trailing_slash_on_the_base_url_does_not_double_up
      Vehicles.configuration.api_base_url += "/"
      request = serve(200, IMAGES_JSON) { @leon.images }

      assert_equal "GET /api/v1/vehicles/car/seat/leon/images HTTP/1.1", request[:line]
    end

    def test_a_path_prefix_on_the_base_url_is_kept
      Vehicles.configuration.api_base_url += "/vdb"
      request = serve(200, IMAGES_JSON) { @leon.images }

      assert_equal "GET /vdb/api/v1/vehicles/car/seat/leon/images HTTP/1.1", request[:line]
    end

    # What 0.7.8 hit in production: the site's HTML 404 at /v1/...
    def test_a_404_html_page_is_nil
      result = :unset
      serve(404, "<!doctype html><h1>Not found</h1>", "text/html") { result = @leon.images }

      assert_nil result
    end

    def test_an_unauthorized_key_is_nil
      result = :unset
      serve(401, %({"error":"unauthorized"})) { result = @leon.image }

      assert_nil result
    end

    def test_the_result_says_why_with_the_apis_own_code
      result = nil
      serve(402, %({"error":"insufficient_credits","balance":0})) { result = @leon.images_result }

      assert_equal [:payment_required, 402, "insufficient_credits"], [result.reason, result.status, result.error]
      assert_equal "/api/v1/vehicles/car/seat/leon/images", result.path
    end

    def test_a_timeout_is_a_reason
      Vehicles.configuration.api_timeout = 0.3
      held = []
      thread = Thread.new { held << @server.accept }
      result = @leon.images_result

      assert_equal :timeout, result.reason
    ensure
      thread&.join(1)
      held&.each(&:close)
    end

    # A dataset release renamed the record: the API answers 301 to the
    # successor's images URL (query kept). Until 0.9.1 the gem dropped it.
    def test_a_former_id_redirect_is_followed_with_the_key
      port = @server.addr[1]
      requests = serve_each(
        [301, %({"error":"moved_permanently"}),
         { "Location" => "http://127.0.0.1:#{port}/api/v1/vehicles/car/seat/leon-new/images?color=white" }],
        [200, IMAGES_JSON]
      ) { @url = @leon.image(color: "white") }

      assert_equal "https://cdn.example/leon-white-md.webp", @url
      assert_equal "GET /api/v1/vehicles/car/seat/leon-new/images?color=white HTTP/1.1", requests[1][:line]
      assert_equal "Bearer secret", requests[1][:headers]["authorization"]
    end

    def test_a_redirect_to_another_host_is_not_followed
      requests = serve_each(
        [301, "{}", { "Location" => "https://evil.example/steal" }]
      ) { @result = @leon.images_result }

      assert_equal 1, requests.size
      assert_equal [:invalid_response, 301], [@result.reason, @result.status]
    end

    def test_a_200_that_is_not_json_is_nil
      result = :unset
      serve(200, "<html>maintenance</html>", "text/html") { result = @leon.images }

      assert_nil result
    end

    def test_an_unreachable_api_is_nil
      port = @server.addr[1]
      @server.close # nothing listens there now: connection refused

      Vehicles.configuration.api_base_url = "http://127.0.0.1:#{port}"

      assert_nil @leon.image
      assert_nil @leon.images
    end

    # Net::HTTP retries an idempotent GET after a read timeout by default:
    # for a billed endpoint that is two charges and twice the latency.
    def test_a_slow_api_is_asked_once_and_answers_nil
      Vehicles.configuration.api_timeout = 0.3
      accepted = 0
      held = []
      thread = Thread.new do
        loop do
          held << @server.accept # read nothing, answer nothing: a read timeout
          accepted += 1
        end
      rescue IOError, Errno::EBADF
        nil
      end

      assert_nil @leon.images
      sleep 0.3 # room for a retry to connect, if one were coming

      assert_equal 1, accepted
    ensure
      held&.each(&:close)
      @server.close
      thread&.join(1)
    end

    IMAGES_JSON = JSON.generate(
      "id" => "car/seat/leon", "color" => "white", "requested_color" => "white",
      "palette" => %w[white grey],
      "variants" => {
        "sm" => { "url" => "https://cdn.example/leon-white-sm.webp", "width" => 320, "height" => 180 },
        "md" => { "url" => "https://cdn.example/leon-white-md.webp", "width" => 640, "height" => 360 },
        "lg" => { "url" => "https://cdn.example/leon-white-lg.webp", "width" => 1280, "height" => 720 }
      }
    )

    private

    # Answer one request per [status, body, headers] in order; returns them.
    def serve_each(*answers)
      captured = []
      thread = Thread.new do
        answers.each do |status, body, headers|
          client = @server.accept
          request = { line: client.gets.to_s.chomp, headers: {} }
          while (header = client.gets.to_s.chomp) != ""
            name, value = header.split(": ", 2)
            request[:headers][name.downcase] = value
          end
          captured << request
          extra = (headers || {}).map { |k, v| "#{k}: #{v}\r\n" }.join
          client.write "HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\n#{extra}" \
                       "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
          client.close
        end
      end
      yield
      thread.join(5)
      captured
    end

    # Answer exactly one request with `status`/`body` while the block runs;
    # returns the request as received ({ line:, headers: }).
    def serve(status, body, content_type = "application/json")
      captured = {}
      thread = Thread.new do
        client = @server.accept
        captured[:line] = client.gets.to_s.chomp
        captured[:headers] = {}
        while (header = client.gets.to_s.chomp) != ""
          name, value = header.split(": ", 2)
          captured[:headers][name.downcase] = value
        end
        client.write "HTTP/1.1 #{status} X\r\nContent-Type: #{content_type}\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
        client.close
      end
      yield
      thread.join(5)
      captured
    end
  end
end
