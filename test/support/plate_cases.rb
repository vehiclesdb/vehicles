# frozen_string_literal: true

require_relative "regex_samples"

module Vehicles
  # The serials a jurisdiction's formatting is exercised on: for every series,
  # samples generated from its regex and its strict twin (RegexSamples), plus
  # four serials generated from its display pattern; every serial is offered
  # to every series of the jurisdiction. Separator-free and upper-cased, as
  # Vehicles.plate canonicalises them.
  module PlateCases
    STRIP = /[\s\-–—·.]+/

    module_function

    def for(jurisdiction)
      raw = jurisdiction.series.flat_map do |s|
        seed = s.id.sum
        from_regex = [s.regex, s.regex_strict].compact.flat_map { |src| RegexSamples.samples(src, seed: seed) }
        from_regex + pattern_samples(s, seed)
      end
      raw.map { |x| x.upcase.gsub(STRIP, "") }.reject(&:empty?).uniq
    end

    def pattern_samples(series, seed, count = 4)
      pat = series.pattern or return []
      rng = Random.new(seed)
      Array.new(count) do
        out = +""
        chars = pat.chars
        i = 0
        while i < chars.size
          c = chars[i]
          if c == "\\"
            out << chars[i + 1].to_s
            i += 2
            next
          end
          out << (if c == "9" then rng.rand(10).to_s
                  elsif c == "L" then ("A".."Z").to_a[rng.rand(26)]
                  else c
                  end)
          i += 1
        end
        out
      end
    end
  end
end
