# frozen_string_literal: true

module Vehicles
  # The model-resolution ladder behind Vehicles.match_model (0.9.0); its exact
  # rungs a–c are also what Vehicles.model answers, and Vehicles.identify
  # (TextMatcher) runs it after splitting off the make. Rung names and
  # confidences follow the cross-surface contract (vehiclesdb RESOLUTION.md
  # §3 — rungs 3–5, 7, 8 there):
  #   a. :fold    — Make#model exactly (name/slug, spacing-blind, "Serie N")
  #   b. :alias   — a published model alias (Model#aliases)
  #   c. :form    — a curated registry spelling (Model#forms)
  #   d. :cleaned — peel an echoed make name and "new" fillers, retry a–c
  #   e. :fuzzy   — bounded edit distance over names, aliases and forms
  # Any answer reached through a typo-corrected make is :fuzzy as well.
  #
  # The one rule above all: never a confident WRONG answer. Hence:
  #   - b and c are curated data (normalized equality, then spacing-blind
  #     equality), not guesses; a hit on two different model slugs is
  #     AMBIGUOUS and STOPS the ladder — a weaker rung must never overrule
  #     the data saying "this could be either";
  #   - d peels whole tokens only: a COMPLETE make name/alias anchored at the
  #     start ("Citroën C3", "Lynk And Co 01"), never a partial one ("Healey
  #     Sprite" is not "Austin-Healey Sprite" to this rung — a form says so);
  #   - e never edits a word containing a digit ("2008" is never "208") and
  #     never stacks on a typo-corrected make;
  #   - no prefix / truncation heuristics: they pick the wrong family ("C3
  #     Aircr" is the C3 Aircross, "Megane Conquest" is the Arkana) — curated
  #     forms carry those.
  # Machine input (ids, slugs, paths — Fuzzy.eligible_input?) only ever
  # takes the exact rungs a–c.
  module ModelMatcher
    CONFIDENCE = ModelMatch::CONFIDENCE

    # "New" in the languages registries and dealers write: "Nuevo C4", "Neue
    # A-Klasse". Only ever peeled as a WHOLE leading token, and never when it
    # is itself one of the make's model names (Chevrolet "Nova", Opel "Nova").
    FILLERS = %w[nuevo nueva new neu neue nouveau nouvelle nuovo nuova novo nova].to_h { |w| [w, true] }.freeze

    # Words this long may be two edits off in the typo rung; shorter ones one.
    # Measured: "Rapide"/"Rapier", "Exige"/"Elise", "Commando"/"Commander" are
    # two edits apart and all real, different cars.
    LONG_WORD = 9

    module_function

    # The full ladder a–e. A ModelMatch, or nil when nothing matched at all.
    def match(make_query, model_query, kind: nil, kinds: nil)
      make, via, make_typo = resolve_make(make_query)
      return nil unless make

      ladder(make, model_query, KindRule.scope(kind, kinds), KindRule.via(kind, kinds) + via,
             make_query: make_query, make_typo: make_typo)
    end

    # The model half of the ladder on a resolved make: a–c, then (for
    # human-shaped input) d and e.
    def ladder(make, model_query, kind, via, make_query:, make_typo:)
      query = Vehicles.normalize(model_query)
      return non_latin_alias(make, model_query, kind, via) if query.empty?

      exact = rungs(make, query, kind, via, typo_caps(make_typo, cleaned: false))
      return exact if exact
      # Ids/slugs/paths resolve exactly or not at all (same rule as makes),
      # checked per raw TOKEN like the text entry (RESOLUTION.md §4), so
      # "New alpha-z" is machine input here exactly as it is in identify().
      return nil unless Fuzzy.eligible_input?(model_query) &&
                        model_query.to_s.split.all? { |t| Fuzzy.eligible_input?(t) }

      heuristic(make, query, kind, via, make_query: make_query, make_typo: make_typo)
    end

    # Rungs a–c only, on a resolved Make — what Vehicles.model answers. Rung a
    # is Make#model itself, so every pair that resolved before 0.9.0 resolves
    # identically; b–c are curated evidence, so on by default. A Model, or nil
    # (an ambiguous spelling is nil, exactly as it stops match_model).
    def exact(make, model_query, kind: nil)
      query = Vehicles.normalize(model_query)
      found = query.empty? ? non_latin_alias(make, model_query, kind, []) : rungs(make, query, kind, [], [])
      found&.model
    end

    # --- rungs ---------------------------------------------------------------

    # a → b → c on one normalized query. A ModelMatch (possibly ambiguous) or
    # nil. `caps` are weaker rungs that also apply (see #build).
    def rungs(make, query, kind, via, caps)
      strict(make, query, kind, via, caps) || curated(make, query, kind, via, caps)
    end

    # The rungs a match inherits from earlier steps: a cleanup (d) and a
    # typo-corrected make (the make itself was a guess → :fuzzy).
    def typo_caps(make_typo, cleaned:)
      [(:cleaned if cleaned), (:fuzzy if make_typo)].compact
    end

    # a.
    def strict(make, query, kind, via, caps)
      matches, how = make.strict_lookup(query, kind: kind)
      return nil unless matches

      # Two DIFFERENT records with one name → ambiguous (RESOLUTION.md §3), never a coin-flip.
      return ambiguous(matches, :fold, via + ["fold:#{query}"]) if how == :ambiguous || matches.uniq(&:model_slug)[1]

      model = make.pick(matches)
      # A plain name/slug hit transforms nothing; spacing / "Serie N" do.
      steps = how == :name ? [] : ["fold:#{query}→#{model.model_slug}"]
      build(model, matches, [:fold, *caps], via + steps)
    end

    # b, c.
    def curated(make, query, kind, via, caps)
      %i[alias form].each do |field|
        hits, = make.curated_lookup(field, query, kind: kind)
        next if hits.empty?

        return decide(make, hits, field, via + ["#{field}:#{query}"], caps)
      end
      nil
    end

    # d, then e. Peel one leading token group at a time and retry a–c after
    # each peel, so the SHORTEST cleanup that matches wins ("Jensen
    # Jensen-Healey" is the Jensen-Healey, not a "Healey" after peeling
    # "jensen" twice). Whatever is left goes to the typo rung.
    def heuristic(make, query, kind, via, make_query:, make_typo:)
      steps = []
      while (peeled = peel(make, query, make_query, make_typo))
        query, step = peeled
        steps << step
        return nil if query.empty? # "Honda | Honda": a make, not a model

        retried = rungs(make, query, kind, via + steps, typo_caps(make_typo, cleaned: true))
        return retried if retried
      end
      # No stacking: a guessed make plus a guessed model is two guesses.
      make_typo ? nil : typo(make, query, kind, via + steps)
    end

    # d. One peel: drop the leading token group that is not part of the model
    # — a complete make name/alias echoed back ("Citroën C3", "Lynk And Co
    # 01") or a "new" filler ("Nuevo C4"). [rest, step], or nil when the head
    # is neither. Tokens that are themselves a model name or alias of the
    # make are never peeled.
    def peel(make, query, make_query, make_typo)
      tokens = query.split
      head = tokens.first
      return nil if head.nil?
      return [tokens.drop(1).join(" "), "filler:#{head}"] if FILLERS[head] && !make.model_word?(head)

      echo = make_echoes(make, make_query, make_typo).find do |e|
        tokens.first(e.size) == e && !make.model_word?(e.join(" "))
      end
      echo && [tokens.drop(echo.size).join(" "), "make_echo:#{echo.join(" ")}"]
    end

    # e. The single model whose name/alias/form is closest to the query by
    # edit distance. Stricter than the make typo rules (Fuzzy), because model
    # names are short, numerous and full of near-identical codes. Compared
    # WORD BY WORD (same number of words; spacing slips are rung a's job):
    #   - every word keeps its first letter;
    #   - a word containing a digit must be IDENTICAL: "2008"/"208",
    #     "308"/"3008", "TRX250R"/"TLR250R", "XR200A"/"XR200R" are different
    #     vehicles, not typos of each other;
    #   - a word that differs must be at least Fuzzy::MIN_LENGTH long on both
    #     sides: short tokens are trims and codes ("Passat GT" is not the
    #     "Passat GL" one edit away; "Cdi", "Xgt" are nothing);
    #   - one edit per differing word, two only from LONG_WORD letters;
    #   - at most Fuzzy.budget(length) edits in total.
    # The closest model must be unique; a tie is ambiguous.
    def typo(make, query, kind, via)
      return nil if query.length < Fuzzy::MIN_LENGTH

      ranked = typo_hits(make, query, kind).values.sort_by(&:first)
      return nil if ranked.empty?

      top, runner = ranked
      if runner && runner[0] == top[0]
        tied = ranked.take_while { |r| r[0] == top[0] }.flat_map(&:last)
        return ambiguous(tied, :fuzzy, via + ["model_typo:#{query}"])
      end
      _dist, key, models = top
      build(make.pick(models), models, [:fuzzy], via + ["model_typo:#{query}→#{key}"])
    end

    # { model slug => [distance, key, [models at that distance]] } for every
    # name/alias/form within the typo rules.
    def typo_hits(make, query, kind)
      limit = Fuzzy.budget(query.length)
      words = query.split
      allowed = KindRule.symbols(kind)
      best = {}
      make.typo_keys.each do |key, model|
        next unless KindRule.allows?(allowed, model)
        next if (key.length - query.length).abs > limit
        next unless (dist = word_distance(words, key, limit))

        entry = best[model.model_slug]
        if entry.nil? || dist < entry[0]
          best[model.model_slug] = [dist, key, [model]]
        elsif dist == entry[0] && entry[2].none? { |m| m.equal?(model) }
          entry[2] << model
        end
      end
      best
    end

    # Total word-by-word edit distance from the query words to `key` under the
    # typo rules above, or nil when any rule fails.
    def word_distance(words, key, limit)
      keys = key.split
      return nil unless keys.size == words.size

      total = 0
      words.zip(keys) do |word, other|
        next if word == other
        return nil unless typo_pair?(word, other)

        budget = word.length >= LONG_WORD ? 2 : 1
        dist = Fuzzy.distance(word, other, budget)
        return nil if dist > budget || (total += dist) > limit
      end
      total.zero? ? nil : total
    end

    # May these two (different) words be a typo of each other at all?
    def typo_pair?(word, other)
      word[0] == other[0] && !word.match?(/\d/) && !other.match?(/\d/) &&
        word.length >= Fuzzy::MIN_LENGTH && other.length >= Fuzzy::MIN_LENGTH
    end

    # --- helpers -------------------------------------------------------------

    # [make, via, typo_corrected?]. The make's own name/slug leaves no trace;
    # an alias ("vw") and a typo ("volkswagon") are recorded.
    # `fuzzy: false` skips the make typo pass (TextMatcher tries every split
    # exactly before any typo).
    def resolve_make(make_query, fuzzy: true)
      return [make_query, [], false] if make_query.is_a?(Make)

      ds = Vehicles.dataset
      key = Vehicles.normalize(make_query)
      if (make = ds.find_make(make_query, fuzzy: false))
        own = key.empty? || key == Vehicles.normalize(make.name) || key == Vehicles.normalize(make.slug)
        return [make, own ? [] : ["make_alias:#{key}→#{make.slug}"], false]
      end
      make = fuzzy ? ds.find_make(make_query, fuzzy: true) : nil
      make ? [make, ["make_typo:#{key}→#{make.slug}"], true] : [nil, [], false]
    end

    # Token lists a make answers to, longest first: name, slug, published and
    # built-in aliases, the make as the caller typed it, and "&" read as "and"
    # ("Lynk & Co" is also typed "Lynk And Co").
    def make_echoes(make, make_query, make_typo)
      names = [make.name, make.slug, *make.aliases]
      names << make_query.to_s unless make_typo || make_query.is_a?(Make)
      Dataset::BUILTIN_ALIASES.each { |key, slug| names << key if slug == make.slug }
      names += names.select { |n| n.include?("&") }.map { |n| n.gsub("&", " and ") }
      names.map { |n| Vehicles.normalize(n).split }.reject(&:empty?).uniq.sort_by { |t| -t.size }
    end

    # Native-script model aliases (fold to "" under normalize) match on their
    # raw downcased text.
    def non_latin_alias(make, raw, kind, via)
      hits = make.raw_alias_lookup(raw, kind: kind)
      hits.empty? ? nil : decide(make, hits, :alias, via + ["alias:#{raw.to_s.strip}"], [])
    end

    # One model slug among the hits → that model (its slug appended to the
    # last step of the trail); several → ambiguous.
    def decide(make, hits, rung, trail, caps)
      return ambiguous(hits, rung, trail) unless hits.map(&:model_slug).uniq.one?

      model = make.pick(hits)
      build(model, hits, [rung, *caps], [*trail[0...-1], "#{trail.last}→#{model.model_slug}"])
    end

    # `rungs` are every rung the match rests on; the WEAKEST is reported, with
    # its confidence (a cleaned :form is :cleaned, anything behind a
    # typo-corrected make is :fuzzy). `confidence:` overrides the label (the
    # whole-text alias rung is :alias at 0.90).
    def build(model, hits, rungs, via, confidence: nil)
      rung = rungs.min_by { |r| CONFIDENCE.fetch(r) }
      variants = hits.select { |m| m.model_slug == model.model_slug }.uniq(&:object_id)
      ModelMatch.new(model: model, rung: rung, confidence: confidence || CONFIDENCE.fetch(rung),
                     via: via, candidates: variants)
    end

    def ambiguous(hits, rung, via)
      ModelMatch.new(model: nil, rung: rung, confidence: 0.0, via: via, candidates: hits.uniq(&:object_id))
    end
  end
end
