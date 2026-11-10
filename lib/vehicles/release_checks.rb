# frozen_string_literal: true

require "digest"

module Vehicles
  # The integrity and sanity checks Refresher runs on a downloaded release
  # before it may replace the data in use.
  module ReleaseChecks
    # Slices smaller than this are too small for a ratio to mean anything
    # (a country with 12 buses can lose 2 to a merge).
    FLOOR_MIN_BUCKET = 25

    module_function

    # [reason, detail] or nil.
    def manifest_mismatch(manifest, data, body, dist_key)
      return [:version_mismatch, "#{data["version"]} ≠ #{manifest["version"]}"] if
        data["version"] != manifest["version"]

      sha = manifest.dig("files", dist_key, "sha256")
      return [:checksum_mismatch, dist_key] if sha && Digest::SHA256.hexdigest(body) != sha

      expected = manifest["kinds"]
      return nil unless expected.is_a?(Hash)

      actual = kind_counts(raw_models(data))
      expected.each do |kind, counts|
        want = counts.is_a?(Hash) ? counts["models"] : nil
        next unless want.is_a?(Integer)
        return [:count_mismatch, "#{kind}: #{actual.fetch(kind, 0)} ≠ #{want}"] if actual.fetch(kind, 0) != want
      end
      nil
    end

    # A detail string when some kind or (kind, country) slice of the candidate
    # is below refresh_min_ratio of the data in use; nil when all hold.
    def below_floor(data)
      ratio = Vehicles.configuration.refresh_min_ratio
      return nil if ratio.nil?

      current = Vehicles.dataset.all_models.map { |m| [m.kind.to_s, m.availability] }
      before = bucket_counts(current)
      after = bucket_counts(raw_models(data))
      before.each do |bucket, count|
        next if count < FLOOR_MIN_BUCKET
        return "#{bucket.compact.join("/")}: #{after.fetch(bucket, 0)} < #{ratio} × #{count}" if
          after.fetch(bucket, 0) < ratio * count
      end
      nil
    end

    # [[kind, availability], ...] from a raw payload.
    def raw_models(data)
      data["makes"].flat_map do |make|
        Array(make["models"]).map { |m| [(m["kind"] || "car").to_s, Array(m["availability"])] }
      end
    end

    def kind_counts(pairs)
      pairs.each_with_object(Hash.new(0)) { |(kind, _), h| h[kind] += 1 }
    end

    # { [kind, nil] => n, [kind, country] => n }
    def bucket_counts(pairs)
      pairs.each_with_object(Hash.new(0)) do |(kind, countries), h|
        h[[kind, nil]] += 1
        countries.each { |c| h[[kind, c]] += 1 }
      end
    end
  end
end
