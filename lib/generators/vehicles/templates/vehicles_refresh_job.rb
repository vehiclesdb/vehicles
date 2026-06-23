# frozen_string_literal: true

# Pulls the latest published VehiclesDB dataset into the local cache, so data
# fixes and new makes reach this app WITHOUT a gem upgrade. Schedule it (daily is
# plenty) — e.g. with solid_queue in config/recurring.yml:
#
#   vehicles_refresh:
#     class: VehiclesRefreshJob
#     schedule: every day at 3am
#
# It's safe to run anytime: it never raises, and a failed/partial download leaves
# your current data untouched (the gem keeps serving the cache, or the bundled
# snapshot if there's no cache yet).
class VehiclesRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Vehicles.refresh!
  end
end
