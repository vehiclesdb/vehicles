# frozen_string_literal: true

module Vehicles
  # The answer to Vehicles.match_model: which model a stored make + model pair
  # means, HOW it was found, and the evidence. Immutable value object.
  #
  #   m = Vehicles.match_model("VW", "Tuareg")
  #   m.model       # => #<Vehicles::Model "Volkswagen Touareg" suv>
  #   m.method      # => :typo
  #   m.confidence  # => 0.8
  #   m.via         # => ["make_alias:vw→volkswagen", "typo:tuareg→touareg"]
  #   m.candidates  # => every kind-variant of the answer
  #
  # An AMBIGUOUS match has `model` nil, `ambiguous?` true and the competing
  # models in `candidates` — the data knows several answers and will not pick.
  # (No match at all is not a ModelMatch: match_model returns nil.)
  #
  # `confidence` is a fixed LABEL per method (see CONFIDENCE), not a measured
  # probability: it orders methods by how much evidence they rest on, so an
  # app can pick a threshold ("auto-accept >= 0.9, ask the user below").
  class ModelMatch
    # Strongest first. `name` covers exact name/slug (1.0) and the spacing-blind
    # / "Serie N" equivalences of Make#model (0.97, recorded in `via`).
    CONFIDENCE = { name: 1.0, spacing: 0.97, alias: 0.93, form: 0.92, cleaned: 0.9, typo: 0.8 }.freeze

    # `method` deliberately mirrors the vocabulary above (:name, :alias, :form,
    # :cleaned, :typo). NOTE it shadows Object#method on this class — call
    # `Object.instance_method(:method).bind_call(match, :x)` if you ever need
    # reflection on a ModelMatch.
    attr_reader :model, :method, :confidence, :via, :candidates

    def initialize(model:, method:, confidence:, via:, candidates:)
      @model      = model
      @method     = method
      @confidence = confidence
      @via        = via.dup.freeze
      @candidates = candidates.dup.freeze
      freeze
    end

    def ambiguous?
      model.nil?
    end

    def to_h
      { model: model&.to_h, method: method, confidence: confidence, via: via,
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
      %(#<Vehicles::ModelMatch #{answer} #{method} #{confidence}>)
    end

    protected

    def to_a
      [model, method, confidence, via, candidates]
    end
  end
end
