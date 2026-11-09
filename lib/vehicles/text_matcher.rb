# frozen_string_literal: true

module Vehicles
  # The TEXT entry point of the resolution contract (vehiclesdb RESOLUTION.md
  # §3) behind Vehicles.identify: one free-text string ("vw golf",
  # "MERCEDES-BENZ | SPRINTER", "car/volkswagen/golf") → a ModelMatch.
  #
  # Rungs, strongest first; the first that answers wins and an ambiguous
  # rung stops the ladder:
  #   1. :exact     — the canonical id, verbatim ("car/volkswagen/golf")
  #   2. :former_id — an id a record has replaced (Model#former_ids)
  #   then the make is the LONGEST leading token run that resolves as a make
  #   (every split exactly first, then with make typos) and the rest is the
  #   model, through ModelMatcher's rungs a–c (:fold, :alias, :form);
  #   6. :alias 0.90 — the WHOLE text is one model's published alias,
  #      unambiguous across all makes, and no record is NAMED that;
  #   then ModelMatcher's heuristics (:cleaned, :fuzzy) on the model part.
  # Nothing resolves without a make except rungs 1, 2 and 6: "golf" is nil.
  module TextMatcher
    WHOLE_TEXT_ALIAS = 0.9

    module_function

    def identify(text, kind: nil)
      raw = text.to_s.strip
      return nil if raw.empty?

      hint = ModelMatcher.kind_hint(kind)
      ds = Vehicles.dataset
      by_id(ds.models_by_id(raw), :exact, kind, hint + ["exact:#{raw}"]) ||
        by_id(ds.models_by_former_id(raw), :former_id, kind, hint + ["former_id:#{raw}"]) ||
        by_make(ds, text, kind, hint)
    end

    # Rungs 1–2: ids are explicit, so `kind:` only chooses among kind
    # variants of the same record. Two different records → ambiguous.
    def by_id(hits, rung, kind, via)
      return nil if hits.empty?
      return ModelMatcher.ambiguous(hits, rung, via) unless hits.map { |m| record(m) }.uniq.one?

      model = (kind && hits.find { |m| m.kind == kind.to_sym }) || hits.find(&:car?) || hits.first
      ModelMatcher.build(model, hits, [rung], via)
    end

    def by_make(dataset, text, kind, hint)
      tokens = Vehicles.normalize(text).split
      return nil if tokens.empty?

      # Per raw TOKEN, before normalization (RESOLUTION.md §4): one
      # machine-shaped token disables both typo rungs for the whole text.
      # Checking the whole string missed "marcedes-benz gla" — the space hid
      # the slug-shaped make from Fuzzy's anchored patterns (pre-release
      # review, 2026.11.0).
      eligible = !text.is_a?(Symbol) && text.to_s.split.all? { |t| Fuzzy.eligible_input?(t) }
      make, rest, via, make_typo, prefix = split(tokens, eligible)
      model_part = make && !rest.empty?
      if model_part
        found = ModelMatcher.rungs(make, rest, kind, hint + via, ModelMatcher.typo_caps(make_typo, cleaned: false))
        return found if found
      end
      whole = whole_text_alias(dataset, tokens.join(" "), kind, hint)
      return whole if whole
      return nil unless model_part && eligible

      ModelMatcher.heuristic(make, rest, kind, hint + via, make_query: prefix, make_typo: make_typo)
    end

    # [make, model part, via, make typo?, make prefix] for the longest leading
    # run that is a make — exact over every split first, then (human-shaped
    # input only) with make typos, always leaving a model token. nil if none.
    def split(tokens, eligible)
      [false, true].each do |fuzzy|
        next if fuzzy && !eligible

        (fuzzy ? tokens.size - 1 : tokens.size).downto(1) do |i|
          prefix = tokens[0, i].join(" ")
          make, via, typo = ModelMatcher.resolve_make(prefix, fuzzy: fuzzy)
          return [make, tokens.drop(i).join(" "), via, typo, prefix] if make
        end
      end
      nil
    end

    # Rung 6. Unambiguous ACROSS MAKES (two records → ambiguous), and never
    # when ANOTHER record is named that — a name always outranks an alias
    # ("Rabbit" is a Golf alias AND car/volkswagen/rabbit's name → nil). An
    # alias folding onto its OWN record's name is fine: SEAT publishes
    # "Málaga" on seat/malaga, and "malaga" must answer (SDK adjudication
    # 2026-07-27; RESOLUTION.md rung 6 says "no OTHER record").
    def whole_text_alias(dataset, query, kind, hint)
      hits = dataset.models_by_alias(query)
      hits = hits.select { |m| m.kind == kind.to_sym } if kind
      return nil if hits.empty?
      return nil if (dataset.records_named(query) - hits.map { |m| record(m) }).any?

      via = hint + ["alias:#{query}"]
      return ModelMatcher.ambiguous(hits, :alias, via) unless hits.map { |m| record(m) }.uniq.one?

      model = hits.find(&:car?) || hits.first
      ModelMatcher.build(model, hits, [:alias], [*via[0...-1], "#{via.last}→#{record(model)}"],
                         confidence: WHOLE_TEXT_ALIAS)
    end

    # A record across kinds: "make-slug/model-slug".
    def record(model)
      "#{model.make_slug}/#{model.model_slug}"
    end
  end
end
