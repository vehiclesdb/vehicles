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
        # the plates spec §2.7 (normative): a series says whether a regex hit is a
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
        # The printed-form check behind format_serial's pattern walk: `regex`
        # is the tier the dataset round-trips against `pattern`.
        @pattern_check_regexp = compile(@regex)
        @lenient_regexp    = compile(self.class.strip_separators(@regex_strict || @regex))
        # The series' SHAPE without its issuing alphabet, only where the two
        # differ (a `regex_strict` exists): what Match#near_misses tests.
        @recall_lenient_regexp = @regex_strict && compile(self.class.strip_separators(@regex))
        segments, separators = self.class.segment_separators(@regex_strict || @regex)
        @issued_separators = (separators || []).freeze
        # Repair readings, used ONLY when the display-pattern walk produced a
        # string the regex rejects (see format_serial). They differ from the
        # issued reading in two ways: a regex whose separators sit inside an
        # alternation group (nl-export's union of sidecodes, tr-standard-2014's
        # three letter counts) is split per branch, and a separator class
        # prints the separator the display pattern shows when the class
        # allows it (us-id "[- ]" under "9L 999L" prints a space).
        prefer = @display_pattern ? (@display_pattern.chars & [ " ", "-", "·", "." ]) : []
        sources = self.class.group_expansions(@regex_strict || @regex)
        @repair_readings = sources.filter_map do |src|
          segs, seps = self.class.segment_separators(src, prefer: prefer, balanced: true)
          next unless segs

          [ compile("\\A(#{segs.join(')(')})\\z"),
            compile("\\A(#{segs.map { |seg| self.class.lazy(seg) }.join(')(')})\\z"), seps.freeze ]
        end.freeze
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
      # `regex_strict` being present: The plates spec §2.7 forbids that inference
      # because most strict series need no strict twin (their `regex` already
      # IS the issuing grammar — Portugal's AA-00-AA, the Spanish CD/CC/OI/TA
      # series). Until 0.9.2 the gem inferred it, so 668 strict series
      # (Portugal's whole national range among them) answered "not strict".
      # Consumers validating user input should weight strict hits above
      # recall-only ones — Match does.
      def strict?
        matching != "recall-only"
      end

      # Vehicle categories that carry people (dataset `categories`
      # vocabulary). A series issued only to trailers, semitrailers,
      # caravans, tractors, machines or trucks plates nothing a passenger
      # rides in.
      PASSENGER_CATEGORIES = %w[car van bus coach motorhome motorcycle moped scooter quadricycle tricycle
                                ambulance].freeze

      # Is this series issued to at least one passenger-carrying vehicle
      # category? (es-national-2000: yes; es-trailer-1999 and the
      # es-special-vehicles-1999 tractor plates: no.) Series without
      # categories answer true: unknown is not "no".
      def passenger?
        categories.empty? || categories.intersect?(PASSENGER_CATEGORIES)
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

        out = format_serial_unchecked(serial)
        # Formatting may only insert separators. Anything else (a dropped,
        # duplicated or reordered character) is a damaged string: return the
        # serial as stored instead.
        return serial.dup.freeze unless out.gsub(STRIP_FOR_CHECK, "") == serial.gsub(STRIP_FOR_CHECK, "")

        out
      end

      STRIP_FOR_CHECK = /[\s\-–—·.]+/

      def format_serial_unchecked(serial)
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
          # Only when the walk produced a serial the series' own regex
          # accepts: a variable-length family can fill the slot count with a
          # different shape (ID "BL1234AB" against "L 9999 LLL" walked to
          # "B L123 4AB"), and that must fall through to the regex split.
          return out.freeze if @pattern_check_regexp.nil? || @pattern_check_regexp.match?(out)

          # No unambiguous repair: return exactly what the walk printed, as
          # before the repair existed, rather than falling through to the
          # issued split (whose captures can overlap here).
          return repair_format(serial) || out.freeze
        end

        # Length mismatch: the pattern is one shape of a variable family —
        # reconstruct from the regex segmented at its separators instead
        # (ES provincial: "M1234LA" is M-1234-LA, which the fixed-slot walk
        # sliced into "M1-234L-A").
        if issued_regexp && (m = issued_regexp.match(serial)) &&
            m.captures.size == issued_separators.size + 1
          return self.class.join_groups(m.captures, issued_separators)
        end

        # Neither path can know — unformatted is honest, misplaced
        # separators are not.
        serial.dup.freeze
      end

      # The repair reading for a serial the pattern walk mis-split: format
      # from the one reading that splits it unambiguously; nil when none or
      # several do (the caller then returns the serial as stored).
      def repair_format(serial)
        printed = @repair_readings.filter_map do |greedy, lazy, seps|
          (g = greedy&.match(serial)) or next
          l = lazy&.match(serial)
          next if l.nil? || l.captures != g.captures || g.captures.size != seps.size + 1

          self.class.join_groups(g.captures, seps)
        end.uniq
        printed.first if printed.size == 1
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
      # Rejoin captured groups with their separators. An optional group that
      # matched nothing prints nothing, and neither does the separator in
      # front of it (ID "DK1" is "DK 1", not "DK 1 ").
      def self.join_groups(captures, separators)
        out = +""
        captures.each_with_index do |part, i|
          next if part.nil? || part.empty?

          out << separators[i - 1] if i.positive? && !out.empty?
          out << part
        end
        out.freeze
      end

      # The branches of the FIRST non-nested alternation group in a regex,
      # each spliced back into the full source: "\\A\\d{2} ?(?:X|Y)\\z" gives
      # ["\\A\\d{2} ?X\\z", "\\A\\d{2} ?Y\\z"]. Empty when there is no such
      # group, when it is quantified, or when a branch nests another group.
      # Every non-nested (?:...) group expanded — an alternation into its
      # branches, an optional group "(?:...)?" into present and absent — until
      # none is left: "\\A(?:ET|FN)[- ]\\d+(?:-VE)?\\z" gives four plain
      # sequences. A group with any other quantifier is left as it is (the
      # source then fails segmentation, as before). Capped at 64 variants.
      def self.group_expansions(src)
        return [] if src.nil?

        done = []
        todo = [ src ]
        until todo.empty?
          cur = todo.shift
          branches = alternation_branches(cur)
          if branches.empty?
            done << cur
          else
            todo.concat(branches)
          end
          return [ src ] if done.size + todo.size > 64
        end
        done.uniq
      end

      def self.alternation_branches(src)
        return [] if src.nil?

        chars = src.chars
        i = 0
        while i < chars.size
          if chars[i] == "\\"
            i += 2
            next
          end
          if chars[i] == "["
            i += 1 while i < chars.size && chars[i] != "]"
            i += 1
            next
          end
          break if chars[i, 3].join == "(?:"

          i += 1
        end
        return [] if i >= chars.size

        start = i
        j = i + 3
        alts = [ +"" ]
        while j < chars.size
          ch = chars[j]
          case ch
          when "\\"
            alts.last << ch << chars[j + 1].to_s
            j += 2
          when "["
            k = j
            k += 1 while k < chars.size && chars[k] != "]"
            alts.last << chars[j..k].join
            j = k + 1
          when "("
            return []
          when "|"
            alts << +""
            j += 1
          when ")"
            break
          else
            alts.last << ch
            j += 1
          end
        end
        return [] if j >= chars.size

        after = j + 1
        if chars[after] == "?" && chars[after + 1] != "?"
          alts << +""
          after += 1
        elsif [ "*", "+", "{", "?" ].include?(chars[after])
          return []
        end
        return [] if alts.size < 2

        pre = chars[0...start].join
        post = chars[after..].join
        alts.map { |alt| "#{pre}#{alt}#{post}" }
      end

      def self.balanced_parens?(src)
        parens = src.delete("^()")
        parens.count("(") == parens.count(")")
      end

      def self.segment_separators(src, prefer: [], balanced: false)
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
              members = tokens.map { |tok| tok.start_with?("\\") ? (tok[1] == "s" ? " " : tok[1]) : tok }
              printed = (prefer & members).first || members.first
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
        # A separator inside a group splits the group across segments
        # ("(?:[A-Z]{2}" | "\\d{2}|..."): the result is not a sequence.
        return [ nil, nil ] if balanced && !segments.all? { |s| balanced_parens?(s) }

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
