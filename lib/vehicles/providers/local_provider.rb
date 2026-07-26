# frozen_string_literal: true

module Vehicles
  module Providers
    # The always-available provider, backed by the bundled dataset. It answers
    # whatever the local snapshot knows and returns nil for everything it doesn't
    # (years/segment/image today) — which is exactly what makes graceful
    # degradation work: the hosted provider enriches, this one guarantees the
    # gem never breaks when the hosted data is absent.
    module LocalProvider
      module_function

      def available?
        true
      end

      # The bundled snapshot is make/model/kind/body_type only — richer fields
      # come from the hosted API. Returning nil here lets the resolver move on
      # (and ultimately yield nil) instead of raising.
      def years(_model)                                          = nil
      def segment(_model)                                        = nil
      def image(_model, year: nil, color: nil, size: :md)        = nil
      def images(_model, color: nil)                             = nil
    end
  end
end
