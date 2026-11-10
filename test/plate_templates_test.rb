# frozen_string_literal: true

require "test_helper"
require "socket"

module Vehicles
  # The template client over a REAL socket: exactly what goes on the wire
  # (and what never does: the registration, the API key), caching, and nil
  # on every failure. A local HTTP server plays VehiclesDB.
  class PlateTemplatesTest < TestCase
    FIXTURES = File.expand_path("fixtures/plate_templates", __dir__)
    SPAIN = File.read(File.join(FIXTURES, "es-national-2000.svg"), encoding: "UTF-8")

    def setup
      @server = TCPServer.new("127.0.0.1", 0)
      @requests = Queue.new
      @responses = Hash.new { [404, "<!doctype html><h1>Not found</h1>", "text/html"] }
      @thread = Thread.new { serve_forever }
      Vehicles.configure do |c|
        c.api_key = "secret-key"
        c.api_base_url = "http://127.0.0.1:#{@server.addr[1]}"
      end
    end

    def teardown
      @server.close unless @server.closed?
      @thread.join(1)
      super
    end

    ES_PATH = "/plates/es/es-national-2000/template.svg?shape=NNNN_LLL"

    def test_render_fetches_the_blank_template_and_fills_it_locally
      @responses[ES_PATH] = [200, SPAIN, "image/svg+xml"]

      svg = Plates.render("1234bcd", jurisdiction: :es)

      assert_includes svg, ">1234 BCD</text>"
      assert_includes svg, %(aria-label="Spain plate 1234BCD")
      assert_equal(["GET #{ES_PATH} HTTP/1.1"], requests.map { |r| r[:line] })
    end

    # THE privacy contract: a registration is personal data. Nothing of it
    # may reach VehiclesDB: not the path, not the query, not a header. And
    # the public route gets no API key either.
    def test_no_registration_character_and_no_api_key_leave_the_machine
      @responses[ES_PATH] = [200, SPAIN, "image/svg+xml"]

      Plates.render("9876 XYZ", jurisdiction: :es, label: "Matrícula 9876 XYZ")
      wire = requests

      assert_equal 1, wire.size
      raw = wire.first[:raw]

      %w[9876 XYZ 9876XYZ secret-key].each { |secret| refute_includes raw, secret }
      refute wire.first[:headers].key?("authorization")
    end

    def test_a_template_is_fetched_once_per_series_shape_and_region
      @responses[ES_PATH] = [200, SPAIN, "image/svg+xml"]

      assert Plates.render("1234 BCD", jurisdiction: :es)
      assert Plates.render("5678 FGH", jurisdiction: :es)
      assert_equal 1, requests.size
    end

    def test_a_failure_is_remembered_briefly_not_retried_on_every_call
      assert_nil Plates.template(code: :es, series: "es-national-2000", shape: "NNNN LLL")
      assert_nil Plates.template(code: :es, series: "es-national-2000", shape: "NNNN LLL")
      assert_equal 1, requests.size
    end

    def test_template_sends_shape_and_region_only
      fr = File.read(File.join(FIXTURES, "fr-siv-standard-75.svg"), encoding: "UTF-8")
      @responses["/plates/fr/fr-siv-standard/template.svg?shape=LL-NNN-LL&region=75"] = [200, fr, "image/svg+xml"]

      svg = Plates.template(code: "FR", series: "fr-siv-standard", shape: "LL-NNN-LL", region: "75")

      assert_equal fr, svg
      assert_equal "image/svg+xml", requests.first[:headers]["accept"]
    end

    # Client-side fence: a "shape" that carries characters is refused here,
    # before any request — even if a caller mixes up its arguments.
    def test_a_shape_with_characters_never_leaves
      ["1234_BCD", "NNNN BCD", "NNNN LLL\n", "../x"].each do |shape|
        assert_nil Plates.template(code: :es, series: "es-national-2000", shape: shape), shape
      end
      assert_nil Plates.template(code: "es/../x", series: "es-national-2000")
      assert_nil Plates.template(code: :es, series: "ES 1234", shape: "NNNN LLL")
      ["1234 BCD", "1234BCD", "AB123CD", "B-MW1234", "12345", "123", "0"].each do |region|
        assert_nil Plates.template(code: :fr, series: "fr-siv-standard", shape: "LL-NNN-LL", region: region), region
      end
      assert_empty requests
    end

    def test_an_ambiguous_plate_is_not_drawn_and_asks_nothing
      assert_nil Plates.render("MAB1234", jurisdiction: :de) # M-AB or MA-B: two standard series
      assert_nil Plates.render("not a plate", jurisdiction: :es)
      assert_nil Plates.render("1234BCD", jurisdiction: :zz)
      assert_empty requests
    end

    def test_a_200_that_is_not_a_template_is_nil
      @responses[ES_PATH] = [200, "<svg xmlns='http://www.w3.org/2000/svg'/>", "image/svg+xml"]

      assert_nil Plates.render("1234BCD", jurisdiction: :es)
    end

    def test_a_template_of_an_unknown_schema_is_nil
      @responses[ES_PATH] = [200, SPAIN.sub('{"version":1,', '{"version":2,'), "image/svg+xml"]

      assert_nil Plates.render("1234BCD", jurisdiction: :es)
    end

    # Hosts inline the SVG into their pages: a template with anything active
    # or external is not one.
    def test_a_template_with_active_or_external_content_is_nil
      [SPAIN.sub("<defs>", "<defs><script>alert(1)</script>"),
       SPAIN.sub('role="img"', 'role="img" onload="alert(1)"'),
       SPAIN.sub("<defs>", '<defs><image href="https://evil.example/x.png"/>'),
       SPAIN.sub("<defs>", "<defs><style>a{background:url(https://evil.example/x)}</style>"),
       SPAIN.sub("<defs>", '<defs><svg/onload="alert(1)"></svg>'),
       SPAIN.sub("<defs>", "<defs><image href=https://evil.example/x.png />")].each do |bad|
        Vehicles.configuration.plate_template_cache = Plates::TemplateCache.new
        @responses[ES_PATH] = [200, bad, "image/svg+xml"]

        assert_nil Plates.render("1234BCD", jurisdiction: :es), bad[0, 300]
      end
    end

    def test_the_real_templates_are_inert
      Dir[File.join(FIXTURES, "*.svg")].each do |path|
        assert Plates::TemplateFill.inert?(File.read(path, encoding: "UTF-8")), "#{path} is not inert"
      end
    end

    def test_an_unreachable_server_is_nil
      @server.close

      assert_nil Plates.render("1234BCD", jurisdiction: :es)
    end

    def test_a_host_cache_is_used_with_the_configured_ttl
      store = RecordingCache.new
      Vehicles.configure do |c|
        c.plate_template_cache = store
        c.plate_template_ttl = 604_800
      end
      @responses[ES_PATH] = [200, SPAIN, "image/svg+xml"]

      Plates.render("1234BCD", jurisdiction: :es)
      key, value, ttl = store.writes.first

      assert_match %r{\Avehicles/plate-template/v1/#{Regexp.escape(Vehicles::VERSION)}/}o, key
      assert_includes key, "/es/es-national-2000/NNNN_LLL"
      assert_equal SPAIN, value
      assert_equal 604_800, ttl
      refute_includes key, "1234"
    end

    def test_a_broken_host_cache_costs_the_cache_never_the_plate
      Vehicles.configuration.plate_template_cache = Object.new # no read/write at all
      @responses[ES_PATH] = [200, SPAIN, "image/svg+xml"]

      assert_includes Plates.render("1234BCD", jurisdiction: :es), ">1234 BCD</text>"
    end

    def test_the_in_process_cache_expires_and_stays_bounded
      cache = Plates::TemplateCache.new
      cache.write("a", "x", expires_in: -1)

      assert_nil cache.read("a")
      (Plates::TemplateCache::MAX_ENTRIES + 5).times { |i| cache.write("k#{i}", "v") }

      assert_nil cache.read("k0")
      assert_equal "v", cache.read("k#{Plates::TemplateCache::MAX_ENTRIES + 4}")
    end

    class RecordingCache
      attr_reader :writes

      def initialize = @writes = []
      def read(_key) = nil
      def write(key, value, expires_in:) = @writes << [key, value, expires_in]
    end

    private

    def requests
      sleep 0.05 # let the server thread record the last request
      list = []
      list << @requests.pop until @requests.empty?
      list
    end

    def serve_forever
      loop do
        client = @server.accept
        line = client.gets.to_s.chomp
        raw = "#{line}\n"
        headers = {}
        while (header = client.gets.to_s.chomp) != ""
          raw << header << "\n"
          name, value = header.split(": ", 2)
          headers[name.downcase] = value
        end
        @requests << { line: line, headers: headers, raw: raw }
        status, body, type = @responses[line.split[1]]
        client.write "HTTP/1.1 #{status} X\r\nContent-Type: #{type}\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n"
        client.write body
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
  end
end
