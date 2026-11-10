# frozen_string_literal: true

require "json"

module Vehicles
  module Plates
    # The REFERENCE FILLER for VehiclesDB plate templates — the client half of
    # the privacy-safe template endpoint
    # (GET /plates/:code/:series_id/template.svg, VehiclesDB plate-art spec §9).
    # A client downloads a template once (it carries nothing personal, so it
    # caches publicly) and writes the user's registration into it HERE, on its
    # own machine — a registration is personal data and never travels:
    #
    #   svg = Vehicles::Plates::TemplateFill.fill(template_svg, "1234 BCD")
    #
    # Moved here from the VehiclesDB web app (app/models/plates/template_fill.rb; same logic,
    # plus shape_of and label:), whose renderer will call `fit_size` /
    # `recentered_baseline` from this gem
    # so the fit formula lives once. Deliberately dependency-free (Ruby stdlib
    # `json` only — no Rails, no ActiveSupport, no XML library). Everything it
    # needs is in the template's own <metadata id="vdb-template"> block, written
    # by the VehiclesDB renderer from the same layout pass that renders real
    # serials:
    #   slots[]  one per character group: shape slice, compact start offset,
    #            centre x, baseline, font size, nominal width, max width
    #   advance  how the renderer prices glyph widths (em at size 1) — so a
    #            filled group gets the same textLength a server render would
    #
    # It VALIDATES before it writes: the registration must have exactly the
    # template's shape (N = digit, L = letter; separators are free), so a
    # filled plate never shows characters its layout was not computed for.
    module TemplateFill
      class Error < StandardError; end

      # The template metadata schema this filler understands
      # (`"version"` in the vdb-template block).
      SCHEMA_VERSION = 1
      SEPARATORS = "- .·"
      CLASSES = { "N" => /\A[0-9]\z/, "L" => /\A[A-ZÄÖÜ]\z/ }.freeze
      METADATA = %r{<metadata id="vdb-template"><!\[CDATA\[(.*?)\]\]></metadata>}m

      # A filled template is meant to be inlined into a host page, i.e. trusted as
      # HTML. Real templates are inert: shapes, text, and data: URIs for the face
      # and region art. Anything active or external is refused, here at the fill
      # boundary as well as wherever a template is fetched. data: payloads are
      # blanked before the scan (base64 may spell "/onxy=" by chance).
      ACTIVE_CONTENT = Regexp.union(
        /<\s*(?:script|foreignObject|iframe|object|embed)\b/i,
        %r{[\s/"']on[a-z]+\s*=}i, # also <svg/onload=…>, which HTML parsers accept
        /javascript:/i, /@import/i,
        /href\s*+=\s*+(?!["']?\s*(?:data:|#))/i, /url\(\s*+(?!["']?\s*(?:data:|#))/i
      )
      # Only a data: URI's own alphabet (base64 / percent-encoding) is blanked, so
      # markup after a bare "data:" is still scanned.
      DATA_URI = %r{data:[a-z]+/[a-z0-9.+-]+(?:;[a-z0-9=.+-]+)*,[A-Za-z0-9+/=%._~-]*}i

      module_function

      # True when the SVG carries nothing a browser would run or fetch.
      def inert?(svg)
        !svg.to_s.gsub(DATA_URI, "data:").match?(ACTIVE_CONTENT)
      end

      # The filled SVG document. Raises Error when the template is not one or
      # the registration does not fit its shape. `label:` replaces the whole
      # accessible name (default: "<Country> plate <REGISTRATION>"), e.g.
      # "Matrícula 1234 BCD" for a Spanish-language page.
      def fill(svg, registration, label: nil) # rubocop:disable Metrics/AbcSize -- same logic as the VehiclesDB copy
        inert?(svg) or raise Error, "template carries active or external content; refusing to fill it"
        meta = metadata(svg)
        out = svg.sub(METADATA, "")
        groups(meta, registration).each do |g|
          slot = g[:slot]
          attrs = %( textLength="#{g[:text_length]}")
          pattern = %r{(<text id="#{Regexp.escape(slot["id"])}"[^>]*?)( lengthAdjust="[^"]*")?></text>}
          out.match?(pattern) or raise Error, "placeholder #{slot["id"]} missing from the template"
          out = out.sub(pattern) do
            head = Regexp.last_match(1)
            adjust = g[:squeezed] ? %( lengthAdjust="spacingAndGlyphs") : Regexp.last_match(2).to_s
            head = resized(head, slot, g[:font_size], g[:baseline]) if g[:font_size] != slot["font_size"]
            "#{head}#{adjust}#{attrs}>#{escape(g[:text])}</text>"
          end
        end
        return out.sub(/aria-label="[^"]*?"/) { %(aria-label="#{escape(label.to_s)}") } if label

        out.sub(/(aria-label="[^"]*?) plate template"/) do
          %(#{Regexp.last_match(1)} plate #{escape(normalize(registration))}")
        end
      end

      # The parsed <metadata> block of a template SVG.
      def metadata(svg)
        json = svg.to_s[METADATA, 1] or raise Error, "not a VehiclesDB plate template (no vdb-template metadata)"
        JSON.parse(json)
      end

      # The SHAPE of a serial-like text, as the template endpoint takes it:
      # digits → N, letters → L, separators kept ("1234 BCD" → "NNNN LLL").
      # Nil when a character fits no class. A shape carries no characters, so
      # it is the only thing about a registration that may leave the machine.
      # Pattern escapes ("\9") classify their literal (VehiclesDB's
      # Plates::Template.shape_of, same rules).
      def shape_of(text)
        out = +""
        chars = text.to_s.upcase.chars
        while (ch = chars.shift)
          ch = chars.shift.to_s if ch == "\\"
          out << case ch
                 when /\A[0-9]\z/ then "N"
                 when /\A[A-ZÄÖÜ]\z/ then "L"
                 when /\A[- .·]\z/ then ch
                 else return nil
                 end
        end
        out.squeeze(SEPARATORS)
      end

      # Per slot: the characters it prints and the width they need. Usable on
      # its own by a client that draws text itself (the JSON template carries
      # the same metadata).
      def groups(meta, registration) # rubocop:disable Metrics/AbcSize -- same logic as the VehiclesDB copy
        chars = compact(normalize(registration)).chars
        shape = compact(meta.fetch("shape"))
        unless chars.length == shape.length && chars.each_with_index.all? { |ch, i| CLASSES.fetch(shape[i]).match?(ch) }
          raise Error, "registration does not have the template's shape #{meta["shape"].inspect} " \
                       "(N = digit, L = letter); fetch the template for its shape"
        end

        meta.fetch("slots").map do |slot|
          source = chars[slot["start"], slot["max_chars"]].dup
          text = slot["shape"].gsub(/[NL]/) { source.shift }
          size = slot["font_size"]
          baseline = slot["baseline"]
          # A lone run (nothing printed beside it) refits exactly as the
          # renderer fits a real serial: from its natural size, shrunk only
          # when the real characters overflow the room.
          if (refit = slot["refit"])
            size = refit["size"]
            natural = text_width(text, size, meta.fetch("advance"))
            size = fit_size(size, refit["avail"], natural) if natural > refit["avail"]
            rule = refit["baseline"]
            baseline = recentered_baseline(rule["origin"], size, rule["per_size"]) if rule
          end
          width = text_width(text, size, meta.fetch("advance"))
          squeezed = width > slot["max_width"]
          { slot: slot, text: text, squeezed: squeezed, font_size: size, baseline: baseline,
            text_length: (squeezed ? slot["max_width"] : width).round(1) }
        end
      end

      # THE fit rule, shared with VehiclesDB's Plates::SvgRenderer: a run
      # wider than its room shrinks to 98% of the exact fit.
      def fit_size(size, room, natural_width) = (size * room / natural_width * 0.98).round(2)

      # The re-centred baseline of a lone run, shared with the renderer.
      def recentered_baseline(origin, size, per_size) = (origin + (size * per_size)).round(1)

      # A placeholder's size-proportional attributes at a refitted size.
      def resized(head, slot, size, baseline)
        head = head.sub(/ y="[^"]*"/, %( y="#{baseline}")).sub(/ font-size="[^"]*"/, %( font-size="#{size}"))
        if slot["letter_spacing_em"].to_f.positive?
          head = head.sub(/ letter-spacing="[^"]*"/, %( letter-spacing="#{size * slot["letter_spacing_em"]}"))
        end
        if slot["stroke_width_em"]
          head = head.sub(/ stroke-width="[^"]*"/, %( stroke-width="#{(size * slot["stroke_width_em"]).round(2)}"))
        end
        head
      end

      # The renderer's own width model (SvgRenderer#row_metrics): a uniform
      # statutory pitch, or per-glyph measured advances with a fallback.
      def text_width(text, size, advance)
        return text.length * advance["uniform_em"] * size if advance["uniform_em"]

        table = advance.fetch("em")
        text.chars.sum { |ch| (table[ch] || advance.fetch("fallback_em")) * size }
      end

      def normalize(registration) = registration.to_s.strip.upcase

      def compact(text) = text.delete(SEPARATORS)

      def escape(text)
        text.gsub(/[&<>"']/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&#39;")
      end
    end
  end
end
