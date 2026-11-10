# frozen_string_literal: true

module Vehicles
  # What Vehicles.refresh did, and why. Immutable; never raised.
  #
  #   result = Vehicles.refresh
  #   result.status            # => :updated | :current | :rejected | :failed
  #   result.ok?               # => true for :updated and :current
  #   result.updated?          # => a newer dataset is now on disk (and served)
  #   result.reason            # => nil, or why not (see REASONS)
  #   result.version           # => the release the refresh looked at ("2026.11.2")
  #   result.previous_version  # => the newest dataset this app already had
  #   result.message           # => one human sentence for a log line
  #
  # :current  — the published release is the one you already have; nothing
  #             was downloaded (the manifest answered).
  # :rejected — the release exists but is not safe to serve here, so it was
  #             NOT written: an unsupported schema, older than your data, a
  #             checksum or count mismatch, a payload far smaller than your
  #             data (`config.refresh_min_ratio`), or your `refresh_guard`.
  # :failed   — the network or the CDN let you down; try again later.
  class RefreshResult
    STATUSES = %i[updated current rejected failed].freeze

    REASONS = {
      schema_unsupported: "the release uses a dataset schema this gem version does not read",
      older: "the release is older than the data this app already has",
      version_mismatch: "the payload's version is not the version the manifest announced",
      checksum_mismatch: "the payload does not match the manifest's checksum",
      count_mismatch: "the payload's model counts do not match the manifest",
      below_floor: "the payload has far fewer models than the data this app already has",
      guard: "config.refresh_guard refused the release",
      invalid_payload: "the download is not a VehiclesDB dataset",
      manifest_unavailable: "the release manifest could not be fetched or read",
      download_failed: "the dataset download failed",
      write_failed: "the dataset could not be written to config.cache_path",
      error: "an unexpected error"
    }.freeze

    attr_reader :status, :reason, :version, :previous_version, :detail

    def initialize(status:, reason: nil, version: nil, previous_version: nil, detail: nil)
      @status = status
      @reason = reason
      @version = version&.to_s
      @previous_version = previous_version&.to_s
      @detail = detail
      freeze
    end

    def ok? = %i[updated current].include?(status)
    def updated? = status == :updated
    def current? = status == :current
    def rejected? = status == :rejected
    def failed? = status == :failed

    def message
      case status
      when :updated then "dataset #{previous_version} → #{version}"
      when :current then "dataset #{previous_version} is current"
      else
        text = REASONS.fetch(reason, reason.to_s)
        text = "#{text} (#{detail})" if detail
        "refresh #{status} #{version}: #{text}".squeeze(" ")
      end
    end

    def to_h
      { status: status, reason: reason, version: version, previous_version: previous_version, detail: detail }
    end

    def inspect = %(#<Vehicles::RefreshResult #{status}#{" #{reason}" if reason} #{message.inspect}>)
  end
end
