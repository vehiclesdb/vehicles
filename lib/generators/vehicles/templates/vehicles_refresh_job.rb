# frozen_string_literal: true

# Pulls the latest published VehiclesDB dataset into the local cache, so data
# fixes and new makes reach this app WITHOUT a gem upgrade. Schedule it (daily is
# plenty) — e.g. with solid_queue in config/recurring.yml:
#
#   vehicles_refresh:
#     class: VehiclesRefreshJob
#     schedule: every day at 3am
#
# Safe to run anytime and from ONE place: it reads the release manifest first
# (nothing is downloaded when you are current), never downgrades, never writes
# a release your gem version cannot read or one that lost a chunk of your data,
# and never raises. Every process (web workers, other containers sharing
# `config.cache_dir`) picks the new file up on its own within a few seconds.
class VehiclesRefreshJob < ApplicationJob
  queue_as :default

  def perform
    # Vehicles.refresh! (true/false) works too; the result says why.
    result = Vehicles.refresh
    Rails.logger.warn("[vehicles] #{result.message}") unless result.ok?
  end
end
