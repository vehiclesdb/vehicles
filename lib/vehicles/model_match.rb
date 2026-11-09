# frozen_string_literal: true

module Vehicles
  # The answer to Vehicles.match_model / Vehicles.identify: which model a
  # typed make + model (or one free-text string) means, WHICH RUNG of the
  # resolution ladder found it, and the evidence. Immutable value object.
  # Vocabulary and confidences follow the cross-surface contract
  # (vehiclesdb RESOLUTION.md), so the gem, the API and the SDKs agree.
  #
  #   m = Vehicles.match_model("VW", "Tuareg")
  #   m.model       # => #<Vehicles::Model "Volkswagen Touareg" suv>
  #   m.rung        # => :fuzzy
  #   m.confidence  # => 0.8
  #   m.via         # => ["make_alias:vw→volkswagen", "model_typo:tuareg→touareg"]
  #   m.candidates  # => every kind-variant of the answer
  #   m.to_h        # => { ..., method: "fuzzy", ... }  (the API's JSON key)
  #
  # An AMBIGUOUS match has `model` nil, `ambiguous?` true and the competing
  # models in `candidates` — the data knows several answers and will not pick.
  # (No match at all is not a ModelMatch: the resolvers return nil.)
  #
  # `confidence` is a fixed LABEL per rung (see CONFIDENCE), not a measured
  # probability: it orders rungs by how much evidence they rest on, so an app
  # can pick a threshold ("auto-accept >= 0.9, ask the user below").
  class ModelMatch
    # Rung => confidence, strongest first (RESOLUTION.md §3). `fold` is the
    # name/slug match by normalization, spacing-blind and "Serie N" alike.
    # A whole-text alias (Vehicles.identify, no make) is rung :alias at 0.90.
    CONFIDENCE = { exact: 1.0, former_id: 0.98, fold: 0.97, alias: 0.93, form: 0.92,
                   cleaned: 0.9, fuzzy: 0.8 }.freeze

    # Named `rung`, not `method`: that would shadow Object#method. `to_h`
    # still says `method:` (the API's field name), as a String.
    attr_reader :model, :rung, :confidence, :via, :candidates

    def initialize(model:, rung:, confidence:, via:, candidates:)
      @model      = model
      @rung       = rung
      @confidence = confidence
      @via        = via.dup.freeze
      @candidates = candidates.dup.freeze
      freeze
    end

    def ambiguous?
      model.nil?
    end

    def to_h
      { model: model&.to_h, method: rung.to_s, confidence: confidence, via: via,
        candidates: candidates.map(&:to_h), ambiguous: ambiguous? }
    end

    def ==(other)
      other.is_a?(ModelMatch) && other.to_a == to_a
    end
    alias eql? ==

    def hash
      to_a.hash
    end

    def inspect
      answer = ambiguous? ? "ambiguous #{candidates.map(&:full_name).uniq.inspect}" : model.full_name.inspect
      %(#<Vehicles::ModelMatch #{answer} #{rung} #{confidence}>)
    end

    protected

    def to_a
      [model, rung, confidence, via, candidates]
    end
  end
end
