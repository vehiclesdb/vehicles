# frozen_string_literal: true

module Vehicles
  module Plates
    # VehiclesDB's real plate art for a registration, WITHOUT sending the
    # registration anywhere (VehiclesDB PRD-PLATE-ART §9: a plate number is
    # personal data). The plate is fetched as a BLANK template — the series,
    # the registration's shape ("NNNN LLL", character classes only) and an
    # optional region — and filled locally by TemplateFill:
    #
    #   Vehicles::Plates.render("1234 BCD", jurisdiction: :es)
    #   # => "<svg … aria-label=\"Spain plate 1234 BCD\">…</svg>", or nil
    #
    #   Vehicles::Plates.template(code: :es, series: "es-national-2000", shape: "NNNN LLL")
    #   # => the blank template SVG, or nil
    #
    # The template route is public: no API key is needed, and none is sent.
    # Templates are cached (in-process by default; `config.plate_template_cache`
    # takes any store with read(key) / write(key, value, expires_in:), e.g.
    # Rails.cache), so a page view costs at most one request per (series,
    # shape, region) and TTL. Never raises: nil on any failure, so a caller
    # keeps whatever it drew before.
    TEMPLATE_PATH = "/plates/%<code>s/%<series>s/template.svg"
    # A failed fetch is remembered briefly, so an unreachable server costs
    # one timeout per key per window, not one per page view.
    TEMPLATE_MISS_TTL = 300

    # Client-side fences, so nothing but a template request can leave: a
    # shape is N/L classes and separators ("_" is the URL-friendly space),
    # never characters, and the other inputs are identifiers.
    TEMPLATE_CODE = /\A[a-z]{2}(?:-[a-z]{2,3})?\z/
    TEMPLATE_SERIES = /\A[a-z0-9-]+\z/
    TEMPLATE_SHAPE = /\A[NL]+(?:[- .·_][NL]+)*\z/
    # A region is a subdivision KEY, never free text, so a registration
    # passed by mistake cannot leave in it: FR département (75, 2A, 971,
    # 44-bzh), DE Land / CH canton (two letters), AT Land (one digit).
    TEMPLATE_REGION = /\A(?:[0-9]{1,3}|2[AB]|[A-Z]{2}|[0-9]{2}-[A-Z]{3})\z/i
    # Inert-template fence: TemplateFill::ACTIVE_CONTENT (also enforced by
    # TemplateFill.fill itself).
    TEMPLATE_ACTIVE_CONTENT = TemplateFill::ACTIVE_CONTENT

    module_function

    # The blank template SVG for a series, or nil. `shape:` defaults to the
    # series' canonical pattern on the server; `region:` picks region art
    # (FR département, DE/AT Land, CH canton).
    def template(code:, series:, shape: nil, region: nil)
      code = code.to_s.downcase
      series = series.to_s
      shape = shape&.to_s&.tr(" ", "_")
      region = region&.to_s
      return nil unless code.match?(TEMPLATE_CODE) && series.match?(TEMPLATE_SERIES)
      return nil unless (shape.nil? || shape.match?(TEMPLATE_SHAPE)) && (region.nil? || region.match?(TEMPLATE_REGION))

      key = template_cache_key(code, series, shape, region)
      cached = cache_read(key)
      return cached.empty? ? nil : cached if cached.is_a?(String)

      svg = fetch_template(code, series, shape, region)
      cache_write(key, svg || "", svg ? Vehicles.configuration.plate_template_ttl : TEMPLATE_MISS_TTL)
      svg
    rescue StandardError
      nil
    end

    # `registration` drawn on its series' real plate, filled locally, or nil
    # when it cannot be: not a plate of that jurisdiction, more than one
    # standard series it could be (German districts, Italian eras: we would
    # rather draw nothing than the wrong plate), or no template. Only the
    # series, the shape and `region:` are sent. `label:` is the accessible
    # name (TemplateFill.fill).
    def render(registration, jurisdiction:, region: nil, label: nil)
      found = match(registration, jurisdiction: jurisdiction)
      series = template_series(found) or return nil
      shape = TemplateFill.shape_of(series.format_serial(found.canon)) or return nil
      svg = template(code: found.jurisdiction.code, series: series.id, shape: shape, region: region) or return nil
      TemplateFill.fill(svg, registration, label: label)
    rescue StandardError
      nil
    end

    # The one series a match's plate is drawn as: the only standard-class
    # series among the hits, else the only hit. Nil when it is ambiguous.
    def template_series(found)
      standard = found.series.select { |series| series.klass == "standard" }
      return standard.first if standard.one?

      found.series.first if found.series.one?
    end

    def fetch_template(code, series, shape, region)
      params = { shape: shape, region: region }.compact
      body = HTTP.get(HTTP.url(format(TEMPLATE_PATH, code: code, series: series), params),
                      "Accept" => "image/svg+xml")
      return nil unless body

      # Net::HTTP hands back binary; the template is UTF-8 ("·" separators).
      svg = body.dup.force_encoding(Encoding::UTF_8)
      return nil unless svg.valid_encoding?
      return nil unless TemplateFill.inert?(svg)

      svg if TemplateFill.metadata(svg)["version"] == TemplateFill::SCHEMA_VERSION
    rescue TemplateFill::Error, JSON::ParserError
      nil
    end

    # The filler's schema and the gem version are in the key, so an upgrade
    # never fills a template it was not written for; the base URL too, so a
    # development server's templates never answer for production's.
    def template_cache_key(code, series, shape, region)
      ["vehicles/plate-template", "v#{TemplateFill::SCHEMA_VERSION}", Vehicles::VERSION,
       Vehicles.configuration.api_base_url, code, series, shape, region].join("/")
    end

    def cache_read(key)
      Vehicles.configuration.plate_template_cache.read(key)
    rescue StandardError
      nil
    end

    def cache_write(key, value, ttl)
      Vehicles.configuration.plate_template_cache.write(key, value, expires_in: ttl)
    rescue StandardError
      nil
    end

    # The default plate_template_cache: in-process, thread-safe, bounded.
    class TemplateCache
      MAX_ENTRIES = 256

      def initialize
        @entries = {}
        @lock = Mutex.new
      end

      def read(key)
        @lock.synchronize do
          value, expires_at = @entries[key]
          next value if expires_at.nil? || expires_at > now

          @entries.delete(key)
          nil
        end
      end

      def write(key, value, expires_in: nil)
        @lock.synchronize do
          @entries.delete(key)
          @entries.shift while @entries.size >= MAX_ENTRIES
          @entries[key] = [value, expires_in && (now + expires_in.to_f)]
        end
        value
      end

      def clear = @lock.synchronize { @entries.clear }

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
