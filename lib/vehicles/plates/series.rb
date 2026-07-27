# frozen_string_literal: true

module Vehicles
  module Plates
    # One registration series: a pattern identity with a period, a class
    # (standard/taxi/diplomatic/…), categories, sourced design facts, and the
    # two regexes of the dataset's regex policy — `regex` (recall: the
    # pattern's own alphabet) and `regex_strict` (validation: the alphabet
    # the authority actually issues). Validation prefers strict.
    class Series
      attr_reader :id, :klass, :categories, :period, :pattern, :regex,
        :regex_strict, :design, :variants, :sources, :notes,
        :validation_regexp, :lenient_regexp

      def initialize(entry)
        @id           = entry["id"]
        @klass        = entry["class"] || "standard"
        @categories   = Array(entry["categories"]).freeze
        @period       = (entry["period"] || {}).freeze
        @pattern      = entry.dig("format", "pattern")
        @regex        = entry.dig("format", "regex")
        @regex_strict = entry.dig("format", "regex_strict")
        @design       = (entry["design"] || {}).freeze
        @variants     = Array(entry["variants"]).freeze
        @sources      = Array(entry["sources"]).freeze
        @notes        = entry["notes"]
        # Compiled eagerly — the object is frozen, so no lazy memoization.
        @validation_regexp = compile(@regex_strict || @regex)
        @lenient_regexp    = compile(self.class.strip_separators(@regex_strict || @regex))
        freeze
      end

      # A strict-validated series has an authority-alphabet regex twin; a
      # recall-only series (export/dark-blue catch-alls that accept any
      # current shape) matches loosely by design. Consumers validating user
      # input should weight strict hits above recall-only ones — Match does.
      def strict?
        !regex_strict.nil?
      end

      # "2000 →" (open, runs until exhausted) or "1971–2000".
      def period_label
        finish = period["end"]
        finish ? "#{period["start"]}–#{finish}" : "#{period["start"]} →"
      end

      # Re-print a separator-less serial the way this series formats it:
      # walk the pattern; 9/L and literal serial characters consume one input
      # character, separator characters re-emerge from the pattern itself.
      def format_serial(serial)
        return nil if serial.nil? || pattern.nil?

        idx = 0
        out = pattern.each_char.with_object(+"") do |ch, str|
          if [ "-", " ", "·", "." ].include?(ch)
            str << ch
          else
            str << (serial[idx] || "")
            idx += 1
          end
        end
        out.freeze
      end

      # Tokens that read as "a separator" when they make up a whole
      # character class — `[- ]` in the ES consular series is dash-or-space,
      # i.e. a separator spelled as a class.
      SEPARATOR_TOKENS = [ " ", "-", "·", ".", '\s', '\-', '\.', '\ ' ].freeze

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
