# frozen_string_literal: true

module Vehicles
  # Typo tolerance for make lookups (0.7.8): bounded Levenshtein distance,
  # stdlib only. "marcedes" → Mercedes-Benz, "volkswagon" → Volkswagen.
  #
  # Deliberately conservative — a confident WRONG make is worse than none:
  #   - queries under MIN_LENGTH characters never fuzzy-match;
  #   - the edit budget is 1 for 4-5 characters and 2 from 6 up (never more);
  #   - the answer must be UNIQUE: if two different makes tie at the best
  #     distance, the result is nil ("acra": one edit from Acura AND Acma);
  #   - a candidate may never have FEWER words than the query: deleting a
  #     whole word is how a make prefix swallows a model token ("volvo v" is
  #     two edits from "volvo", which turned "Volvo V 60" into Volvo 60);
  #   - every word keeps its first letter (word for word when the counts
  #     match, else the first letter of the query): typos rarely hit the
  #     first letter, model tokens almost always differ there ("citroen e"
  #     is two edits from "citroen ds" — that is the e-C3, not Citroën DS).
  module Fuzzy
    MIN_LENGTH = 4

    module_function

    # Only HUMAN-typed names are fuzzy-matched. Anything shaped like an id, a
    # path or a slug — any "/" ("car/mercedes-benz/c-class", "/makes/marcedes",
    # "marcedes-benz/c-class") or all-lowercase hyphenated ("marcedes-benz") —
    # is machine input: it must resolve exactly or not at all, never to a
    # guessed make (web routing and API ids rely on it; web-session ruling).
    # Symbols are always machine input; so is anything with / _ + or a
    # backslash, a leading/trailing/double hyphen, or a single-case
    # hyphenated token ("marcedes-benz", "MARCEDES-BENZ"). Mixed case
    # ("Marcedes-Benz") and plain words ("marcedes") are human. Verifier
    # finding (0.7.8): each of those machine shapes fuzzed for every typo.
    def eligible_input?(raw)
      return false if raw.is_a?(Symbol)

      s = raw.to_s.strip
      return false if s.match?(%r{[/_+\\]}) || s.start_with?("-") || s.end_with?("-") || s.include?("--")

      !s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)+\z/) && !s.match?(/\A[A-Z0-9]+(?:-[A-Z0-9]+)+\z/)
    end

    # Maximum edit distance allowed for a query of this many characters.
    def budget(length)
      length >= 6 ? 2 : 1
    end

    # The single Make closest to `query` among `keys` ([[normalized key, Make],
    # …]), or nil when nothing is within budget or two makes tie.
    def unique_closest(query, keys)
      return nil if query.length < MIN_LENGTH

      limit = budget(query.length)
      words = query.count(" ") + 1
      best = limit + 1
      hits = {}
      keys.each do |key, make|
        next if (key.length - query.length).abs > limit # cannot be within budget
        next if key.count(" ") + 1 < words              # would swallow a word
        next unless initials_match?(query, key)

        dist = distance(query, key, limit)
        # `distance` reports out-of-budget as limit + 1, the same value `best`
        # starts at — test the LIMIT, or a lone length-compatible key would be
        # accepted at any distance (codex review, 0.7.8: "z" * 28 → a make).
        next if dist > limit || dist > best

        hits = {} if dist < best
        best = dist
        hits[make.slug] = make
      end
      hits.size == 1 ? hits.values.first : nil
    end

    # First letters agree: word for word when both have the same number of
    # words, otherwise (the query has fewer words, "delorean" vs
    # "de lorean") just the first letter.
    def initials_match?(query, key)
      qw = query.split
      kw = key.split
      return qw.first[0] == kw.first[0] unless qw.size == kw.size

      qw.zip(kw).all? { |q, k| q[0] == k[0] }
    end

    # Edit distance (optimal string alignment: Levenshtein plus adjacent
    # transposition = 1 edit, so "telsa" is ONE edit from "tesla" — plain
    # Levenshtein counted it as two and let the one-substitution "temsa" win).
    # Gives up early: returns `limit + 1` once two consecutive rows exceed
    # `limit` (a transposition reads two rows back, so one row is not enough).
    def distance(left, right, limit)
      prev2 = nil
      prev = (0..right.length).to_a
      left.each_char.with_index(1) do |lch, row|
        cur = [row]
        right.each_char.with_index(1) do |rch, col|
          swap = prev2 && col > 1 && lch == right[col - 2] && left[row - 2] == rch
          cur << cell(prev, cur, col, lch == rch, swap ? prev2[col - 2] : nil)
        end
        return limit + 1 if cur.min > limit && prev.min > limit

        prev2 = prev
        prev = cur
      end
      [prev.last, limit + 1].min
    end

    # One DP cell: deletion, insertion, substitution, and — when the two
    # characters are swapped neighbours — transposition from two rows back.
    def cell(prev, cur, col, same, swap_from)
      best = [prev[col] + 1, cur[col - 1] + 1, prev[col - 1] + (same ? 0 : 1)].min
      swap_from ? [best, swap_from + 1].min : best
    end
  end
end
