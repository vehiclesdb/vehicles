# frozen_string_literal: true

module Vehicles
  module Plates
    # One registration series: a pattern identity with a period, a class
    # (standard/taxi/diplomatic/…), categories, sourced design facts, and the
    # two regexes of the dataset's regex policy — `regex` (recall: the
    # pattern's own alphabet) and `regex_strict` (validation: the alphabet
    # the authority actually issues). Validation prefers strict.
    class Series
      attr_reader :id, :klass, :categories, :period, :period_evidence,
        :pattern, :display_pattern, :regex, :regex_strict, :design,
        :variants, :sources, :notes, :validation_regexp, :lenient_regexp,
        :issued_regexp, :issued_separators, :matching, :recall_lenient_regexp,
        :letters

      def initialize(entry)
        @id           = entry["id"]
        @klass        = entry["class"] || "standard"
        # PRD-PLATES §2.7 (normative): a series says whether a regex hit is a
        # validity claim (`strict`) or only a shape hit (`recall-only`).
        # Absent => strict, the spec's backward-compatible default.
        @matching     = entry["matching"] || "strict"
        @categories   = Array(entry["categories"]).freeze
        @period       = (entry["period"] || {}).freeze
        @period_evidence = entry["period_evidence"]
        @pattern      = entry.dig("format", "pattern")
        # "\L" escapes a LITERAL L (vs the any-letter placeholder) —
        # ca-nb-truck-2003 introduced it; resolved for display and walks.
        @display_pattern = @pattern&.gsub(/\\(.)/) { $1 }
        @regex        = entry.dig("format", "regex")
        @regex_strict = entry.dig("format", "regex_strict")
        # The letters this series issues, when the dataset enumerates them
        # (es-national-2000: the 20 consonants). Nil when it does not; a few
        # series carry prose there ("A-Z, no exclusions published"), not a set.
        letters       = entry.dig("format", "charset", "letters")
        @letters      = letters.is_a?(Array) ? letters.map(&:to_s).freeze : nil
        @design       = (entry["design"] || {}).freeze
        @variants     = Array(entry["variants"]).freeze
        @sources      = Array(entry["sources"]).freeze
        @notes        = entry["notes"]
        # Compiled eagerly — the object is frozen, so no lazy memoization.
        @validation_regexp = compile(@regex_strict || @regex)
        @lenient_regexp    = compile(self.class.strip_separators(@regex_strict || @regex))
        # The series' SHAPE without its issuing alphabet, only where the two
        # differ (a `regex_strict` exists): what Match#near_misses tests.
        @recall_lenient_regexp = @regex_strict && compile(self.class.strip_separators(@regex))
        segments, separators = self.class.segment_separators(@regex_strict || @regex)
        @issued_separators = (separators || []).freeze
        @issued_regexp = segments && compile("\\A(#{segments.join(')(')})\\z")
        # The same segmentation with every quantifier lazy. When the greedy
        # and lazy readings of a serial split it differently, the groups are
        # not recoverable from the bare serial ("CD12345" is CD-123-45 or
        # CD-1234-5): format_serial must not pick one.
        @issued_lazy_regexp = segments && compile("\\A(#{segments.map { |seg| self.class.lazy(seg) }.join(')(')})\\z")
        freeze
      end

      # A strict series' regex hit is a validity claim for that series; a
      # recall-only series (export/dark-blue catch-alls that accept any
      # current shape, the ES 1900-1971 numeric era) matches loosely by
      # design. Read from the dataset's `matching:` key, never inferred from
      # `regex_strict` being present: PRD-PLATES §2.7 forbids that inference
      # because most strict series need no strict twin (their `regex` already
      # IS the issuing grammar — Portugal's AA-00-AA, the Spanish CD/CC/OI/TA
      # series). Until 0.9.2 the gem inferred it, so 668 strict series
      # (Portugal's whole national range among them) answered "not strict".
      # Consumers validating user input should weight strict hits above
      # recall-only ones — Match does.
      def strict?
        matching != "recall-only"
      end

      # period_evidence values on which the recorded START is not (or not
      # provenly) the series' birth — an instrument/consolidation date, an
      # upper bound, or an unverified secondary (the dataset's own honesty
      # discipline). The label must not present these as the era. Values
      # like enabling-instrument / statutory-creation-date /
      # instrument-dated-both-ends ARE true starts and stay unmarked.
      INSTRUMENT_DATED_EVIDENCE = %w[
        instrument-in-force instrument-window
        instrument-in-force-upper-bound secondary-locator-unverified
      ].freeze

      # "2000 → today" (open, still issued), "1971–2000", or — when the
      # start is only an instrument date — "~1999–2000" / "~2000 → today":
      # the format is documented FROM that year and may be older.
      # es-provincial's 1999–2000 instrument window over a format that ran
      # for decades is the case this guards. approximate_start? tells a
      # consumer to explain the "~".
      def period_label
        start = period["start"]
        start = "~#{start}" if approximate_start?
        finish = period["end"]
        finish ? "#{start}–#{finish}" : "#{start} → today"
      end

      # True when the recorded start is an instrument date, not the series'
      # birth — the display should read it as "documented from", not "began in".
      def approximate_start?
        INSTRUMENT_DATED_EVIDENCE.include?(period_evidence)
      end

      # Re-print a separator-less serial the way this series formats it.
      # Primary path: match the serial against the regex SEGMENTED at its
      # separators (the §2.6/§2.8 separator contract makes segmentation
      # mechanical) and rejoin the captured groups with the separators the
      # series actually prints — correct even when groups are
      # variable-length (ES provincial: M-1234-LA and SE-1234-AB both live
      # in [A-Z]{1,2}-\d{4}-[A-Z]{1,2}; the old pattern walk sliced
      # "M1234LA" into "M1-234L-A"). Fallback: the pattern walk, but ONLY
      # when the serial exactly fills the pattern's slots; otherwise the
      # serial comes back untouched — unformatted is honest, misplaced
      # separators are not.
      def format_serial(serial)
        return nil if serial.nil?

        # A serial whose groups the series' own regex can split more than one
        # way is returned as stored, before anything else: the bare serial
        # cannot say which split was issued ("CD123456" is CD-123-456 or
        # CD-12-3456; the dataset calls CD-999-999 representative), and a
        # display pattern of one shape must not decide it.
        return serial.dup.freeze if ambiguous_split?(serial)

        # The display pattern is authoritative when the serial fills it
        # exactly and the regex has only one reading of it.
        slots = display_pattern&.each_char&.count { |ch| ![ "-", " ", "·", "." ].include?(ch) }
        if slots && serial.length == slots
          idx = 0
          out = display_pattern.each_char.with_object(+"") do |ch, str|
            if [ "-", " ", "·", "." ].include?(ch)
              str << ch
            else
              str << (serial[idx] || "")
              idx += 1
            end
          end
          return out.freeze
        end

        # Length mismatch: the pattern is one shape of a variable family —
        # reconstruct from the regex segmented at its separators instead
        # (ES provincial: "M1234LA" is M-1234-LA, which the fixed-slot walk
        # sliced into "M1-234L-A").
        if issued_regexp && (m = issued_regexp.match(serial)) &&
            m.captures.size == issued_separators.size + 1
          return m.captures.each_with_index
                  .map { |part, i| i.zero? ? part : "#{issued_separators[i - 1]}#{part}" }
                  .join.freeze
        end

        # Neither path can know — unformatted is honest, misplaced
        # separators are not.
        serial.dup.freeze
      end

      # Tokens that read as "a separator" when they make up a whole
      # character class — `[- ]` in the ES consular series is dash-or-space,
      # i.e. a separator spelled as a class.
      SEPARATOR_TOKENS = [ " ", "-", "·", ".", '\s', '\-', '\.', '\ ' ].freeze

      # Removing a separator can join two repetitions of the same character
      # class: `[A-Z0-9]+(?:-[A-Z0-9]+)*` becomes the redundant
      # `[A-Z0-9]+(?:[A-Z0-9]+)*`. Ruby (3.1+) warns while compiling that shape.
      # Its language is exactly `[A-Z0-9]+`, whether the trailing group is
      # optional or repeated, so canonicalize it after the separator walk.
      REDUNDANT_CHARACTER_CLASS_REPEAT = /(\[[^\]]+\])\+\(\?:\1\+\)[*?]/

      # Split a regex source into its serial SEGMENTS and the separator
      # character printed between each pair — the reconstruction data behind
      # format_serial. Same scan as strip_separators (same class-vs-range
      # discipline; a dropped separator's dangling quantifier goes with it),
      # but instead of discarding separators it records what each one PRINTS
      # (`\s` and "\ " print a space; a separator-only class prints its
      # first token). Returns [segments, separators] with
      # segments.length == separators.length + 1, or [nil, nil] when the
      # source is nil, has no separators, or segments in a shape the
      # reconstruction cannot trust (empty segment, capturing groups that
      # would shift the positional captures).
      def self.segment_separators(src)
        return [ nil, nil ] if src.nil?

        body = src.sub('\A', "").sub('\z', "")
        segments = [ +"" ]
        separators = []
        emit = lambda do |printed|
          if segments.last.empty? && separators.any?
            # a run of separators prints once — keep the first
          else
            separators << printed
            segments << +""
          end
        end

        chars = body.chars
        i = 0
        while i < chars.size
          ch = chars[i]

          if ch == "\\" && i + 1 < chars.size
            nxt = chars[i + 1]
            if [ "s", " " ].include?(nxt)
              i += 2
              i += 1 if [ "?", "*" ].include?(chars[i])
              emit.call(" ")
            elsif [ "-", "." ].include?(nxt)
              i += 2
              i += 1 if [ "?", "*" ].include?(chars[i])
              emit.call(nxt)
            else
              segments.last << ch << nxt
              i += 2
            end
            next
          end

          if ch == "["
            closing = i + 1
            closing += 1 while closing < chars.size && chars[closing] != "]"
            content = chars[(i + 1)...closing].join
            tokens = content.scan(/\\.|./m)
            if tokens.any? && tokens.all? { |t| SEPARATOR_TOKENS.include?(t) }
              first = tokens.first
              printed = first.start_with?("\\") ? (first[1] == "s" ? " " : first[1]) : first
              i = closing + 1
              i += 1 if [ "?", "*" ].include?(chars[i])
              emit.call(printed)
            else
              segments.last << chars[i..closing].join
              i = closing + 1
            end
            next
          end

          if [ "-", " ", "·" ].include?(ch)
            i += 1
            i += 1 if [ "?", "*" ].include?(chars[i])
            emit.call(ch)
          else
            segments.last << ch
            i += 1
          end
        end

        return [ nil, nil ] if separators.empty?
        return [ nil, nil ] if segments.any?(&:empty?)
        # A capturing group inside a segment would shift the positional
        # captures the reconstruction indexes by — bail to the fallback.
        return [ nil, nil ] if segments.any? { |s| s.match?(/\((?!\?)/) }

        [ segments, separators ]
      end

      # Remove separator LITERALS from a regex source, respecting character
      # classes (the "-" inside [A-Z] is a range, not a separator; a class
      # composed ONLY of separators, like `[- ]`, is a separator and goes).
      # A quantifier left dangling by a removed separator ("-?", "[- ]?") is
      # swallowed with it. Linear scan — regexes in this dataset are simple.
      def self.strip_separators(src)
        return nil if src.nil?

        out = +""
        chars = src.chars
        i = 0
        while i < chars.size
          ch = chars[i]

          if ch == "\\" && i + 1 < chars.size
            nxt = chars[i + 1]
            if [ "s", "-", ".", " " ].include?(nxt)
              i += 2
              i += 1 if [ "?", "*" ].include?(chars[i]) # optional separator: drop its quantifier too
            else
              out << ch << nxt
              i += 2
            end
            next
          end

          if ch == "["
            # Copy or drop the WHOLE class span in one decision.
            closing = i + 1
            closing += 1 while closing < chars.size && chars[closing] != "]"
            content = chars[(i + 1)...closing].join
            tokens = content.scan(/\\.|./m)
            if tokens.any? && tokens.all? { |t| SEPARATOR_TOKENS.include?(t) }
              i = closing + 1
              i += 1 if [ "?", "*" ].include?(chars[i])
            else
              out << chars[i..closing].join
              i = closing + 1
            end
            next
          end

          if [ "-", " ", "·" ].include?(ch)
            i += 1
            i += 1 if [ "?", "*" ].include?(chars[i])
          else
            out << ch
            i += 1
          end
        end
        out.gsub(REDUNDANT_CHARACTER_CLASS_REPEAT) { "#{Regexp.last_match(1)}+" }
      end

      # True when the greedy and lazy readings of the segmented regex split
      # this serial differently.
      def ambiguous_split?(serial)
        greedy = issued_regexp&.match(serial) or return false
        lazy = @issued_lazy_regexp&.match(serial) or return false
        greedy.captures != lazy.captures
      end

      # A regex segment with its quantifiers made lazy (+ *, ?, {m,n}), for
      # the ambiguity check in format_serial. Escapes and character classes
      # are copied untouched.
      def self.lazy(src)
        out = +""
        chars = src.chars
        i = 0
        while i < chars.size
          ch = chars[i]
          if ch == "\\"
            out << ch << chars[i + 1].to_s
            i += 2
          elsif ch == "["
            closing = i + 1
            closing += 1 while closing < chars.size && chars[closing] != "]"
            out << chars[i..closing].join
            i = closing + 1
          else
            out << ch
            out << "?" if [ "+", "*", "}" ].include?(ch) && chars[i + 1] != "?"
            i += 1
          end
        end
        out
      end

      def inspect = %(#<Vehicles::Plates::Series #{id} "#{pattern}">)

      private

      # Bad regex in data must degrade like every other lookup: nil, not raise.
      def compile(source)
        return nil if source.nil?

        Regexp.new(source)
      rescue RegexpError
        nil
      end
    end
  end
end
