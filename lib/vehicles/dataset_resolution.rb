# frozen_string_literal: true

module Vehicles
  # Whole-dataset lookups for Vehicles.identify (TextMatcher), mixed into
  # Dataset: ids, former ids and model aliases across EVERY make, which the
  # per-make indexes (Make#lookup_index) cannot answer.
  module DatasetResolution
    # Models whose canonical id ("car/volkswagen/golf") is exactly `id`.
    def models_by_id(id)
      resolution_index[:id][id.to_s] || []
    end

    # Models that list `id` among their former_ids.
    def models_by_former_id(id)
      resolution_index[:former_id][id.to_s] || []
    end

    # Models (any make) with a published alias normalizing to `key`.
    def models_by_alias(key)
      resolution_index[:alias][key] || []
    end

    # Is some model (any make) NAMED this (normalized)?
    def model_named?(key)
      resolution_index[:name].key?(key)
    end

    private

    # Built once on first use; arrays keep dataset order.
    def resolution_index
      @resolution_index ||= begin
        idx = { id: {}, former_id: {}, alias: {}, name: {} }
        all_models.each do |m|
          (idx[:id]["#{m.kind}/#{m.make_slug}/#{m.model_slug}"] ||= []) << m
          m.former_ids.each { |f| (idx[:former_id][f] ||= []) << m }
          m.aliases.each do |a|
            key = Vehicles.normalize(a)
            (idx[:alias][key] ||= []) << m unless key.empty?
          end
          idx[:name][Vehicles.normalize(m.name)] = true
        end
        idx.each_value(&:freeze).freeze
      end
    end
  end
end
