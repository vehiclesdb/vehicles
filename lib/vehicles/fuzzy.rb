# frozen_string_literal: true

module Vehicles
  # Typo tolerance for make lookups (0.7.8): bounded Levenshtein distance,
  # stdlib only. "marcedes" → Mercedes-Benz, "volkswagon" → Volkswagen.
  #
  # Deliberately conservative — a confident WRONG make is worse than none:
  #   - queries under MIN_LENGTH characters never fuzzy-match;
  #   - the edit budget is 1 for 4-5 characters and 2 from 6 up (never more);
  #   - the answer must be UNIQUE: if two different makes tie at the best
  #     distance, the result is nil ("acra": one edit from Acura AND Acma).
  module Fuzzy
    MIN_LENGTH = 4

    module_function

    # Maximum edit distance allowed for a query of this many characters.
    def budget(length)
      length >= 6 ? 2 : 1
    end

    # The single Make closest to `query` among `keys` ([[normalized key, Make],
    # …]), or nil when nothing is within budget or two makes tie.
    def unique_closest(query, keys)
      return nil if query.length < MIN_LENGTH

      limit = budget(query.length)
      best = limit + 1
      hits = {}
      keys.each do |key, make|
        next if (key.length - query.length).abs > limit # cannot be within budget

        dist = distance(query, key, limit)
        next if dist > best

        hits = {} if dist < best
        best = dist
        hits[make.slug] = make
      end
      hits.size == 1 ? hits.values.first : nil
    end

    # Levenshtein distance between two strings, giving up early: returns
    # `limit + 1` as soon as the distance provably exceeds `limit`.
    def distance(left, right, limit)
      prev = (0..right.length).to_a
      left.each_char.with_index(1) do |lch, row|
        cur = [row]
        right.each_char.with_index(1) do |rch, col|
          cur << [prev[col] + 1, cur[col - 1] + 1, prev[col - 1] + (lch == rch ? 0 : 1)].min
        end
        return limit + 1 if cur.min > limit

        prev = cur
      end
      [prev.last, limit + 1].min
    end
  end
end
