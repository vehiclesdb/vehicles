# frozen_string_literal: true

module Vehicles
  # The outcome of one hosted VehiclesDB call, for when `nil` is not enough:
  # WHY there is no image. `Model#image` / `#images` keep answering nil on
  # any failure; `Model#images_result` answers one of these.
  #
  #   r = Vehicles.find("seat leon").images_result(color: "red", exact_color: true)
  #   r.ok?        # => false
  #   r.reason     # => :payment_required
  #   r.error      # => "insufficient_credits" (the API's own code, verbatim)
  #   r.status     # => 402
  #   r.url(:md)   # => nil (the variant URL when ok?)
  #
  # `reason` is coarse and stable (REASONS); `error` is the API's code and can
  # be finer ("no_image", "unknown_color", "unsupported_filter",
  # "insufficient_credits", "invalid_token", …). Client-side reasons have no
  # status: :no_api_key, :timeout, :network, :invalid_response, and
  # :color_not_available (`exact_color: true` and the model is not available in
  # that color — the API would have served another one).
  class HostedResult
    REASONS = %i[ok no_api_key not_found unauthorized payment_required rate_limited invalid_request
                 server_error timeout network invalid_response color_not_available].freeze

    # Reasons that mean "something is wrong with the integration or the
    # service", reported through `config.on_hosted_error` and the logger. A
    # missing image, an unavailable color or no key are normal answers.
    ALERTS = %i[unauthorized payment_required rate_limited invalid_request server_error timeout network
                invalid_response].freeze

    attr_reader :reason, :status, :error, :payload, :path

    def initialize(reason:, status: nil, error: nil, payload: nil, path: nil, cached: false)
      @reason = reason
      @status = status
      @error = error&.to_s
      @payload = payload
      @path = path
      @cached = cached
      freeze
    end

    # Build from an HTTP status (and the API's JSON error body, if any).
    def self.from_status(status, body_error: nil, path: nil)
      reason =
        case status
        when 200..299 then :ok
        when 401, 403 then :unauthorized
        when 402 then :payment_required
        when 404, 410 then :not_found
        when 400, 422 then :invalid_request
        when 429 then :rate_limited
        when 500..599 then :server_error
        else :invalid_response
        end
      new(reason: reason, status: status, error: body_error, path: path)
    end

    def ok? = reason == :ok
    def cached? = @cached
    def alert? = ALERTS.include?(reason)

    # The variant URL for a size (:sm/:md/:lg) when ok?, else nil.
    def url(size = :md)
      ok? ? payload&.dig("variants", size.to_s, "url") : nil
    end

    def with(**changes)
      self.class.new(reason: reason, status: status, error: error, payload: payload, path: path, cached: @cached,
                     **changes)
    end

    def message
      parts = ["VehiclesDB", status, error || reason].compact
      "#{parts.join(" ")} on #{path}"
    end

    # An exception object for error trackers (never raised by the gem).
    def to_error
      HostedError.new(message).tap { |e| e.result = self }
    end

    def to_h
      { reason: reason, status: status, error: error, path: path, cached: cached? }
    end

    def inspect = %(#<Vehicles::HostedResult #{reason}#{" #{status}" if status}#{" #{error}" if error}>)
  end

  # Report-only exception carrying a HostedResult (HostedResult#to_error).
  class HostedError < StandardError
    attr_accessor :result
  end
end
