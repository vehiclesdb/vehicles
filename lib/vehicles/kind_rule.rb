# frozen_string_literal: true

module Vehicles
  # How a kind narrows a lookup, and the ONE kind-collision rule every
  # VehiclesDB surface shares (vehiclesdb RESOLUTION.md §3; lanes B/C,
  # 2026-11-10).
  #
  # A kind collision is one nameplate (same make + model slug) published as
  # several kinds — Iveco "Daily" is a van, a truck and a bus. Not ambiguity:
  # when the caller gave no kind, the answer is the record with
  #   1. the lowest `mass_decile` (unranked last),
  #   2. then the kind order PRECEDENCE (any other kind after these, by
  #      name),
  #   3. then the canonical id.
  # Only among the candidates a rung itself selected: a hit is never widened
  # to sibling kinds that did not match.
  # Backtested on register counts, that picks the kind most registered in 87%
  # of collision groups (the old "car wins" picked it in 43%).
  #
  # `kind:` (one kind) scopes the name rungs; `kinds:` (a list) is a hard
  # filter everywhere, ids included (`kinds: []` allows nothing).
  module KindRule
    PRECEDENCE = %i[van car bus truck moped motorcycle].freeze

    module_function

    # `kind:`/`kinds:` → the allowed kinds as Symbols, or nil for "any". With
    # both, only kinds in both count.
    def scope(kind, kinds)
      return nil if kind.nil? && kinds.nil?

      allowed = kinds.nil? ? nil : symbols(kinds)
      return allowed if kind.nil?

      allowed ? allowed & symbols(kind) : symbols(kind)
    end

    # nil (any), one kind or a list → [Symbol] or nil.
    def symbols(kind)
      kind.nil? ? nil : Array(kind).map { |k| k.to_s.to_sym }
    end

    def allows?(scope, model)
      scope.nil? || scope.include?(model.kind)
    end

    # One record among kind variants of a nameplate (see above).
    def pick(models)
      models.min_by do |m|
        rank = PRECEDENCE.index(m.kind)
        [m.mass_decile || 99, rank ? 0 : 1, rank || 0, rank ? "" : m.kind.to_s, m.id]
      end
    end

    # The `via` steps RESOLUTION.md names: `kind_hint:van`, `kinds:car,van`.
    def via(kind, kinds)
      steps = []
      steps << "kind_hint:#{kind}" if kind
      steps << "kinds:#{Array(kinds).join(",")}" if kinds
      steps
    end
  end
end
