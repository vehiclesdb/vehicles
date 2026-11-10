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

    # Records ("make/model" slugs, any make) NAMED this (normalized).
    def records_named(key)
      resolution_index[:name][key] || []
    end

    # The live Model a retired id now answers to (Vehicles.by_id), or nil:
    #   1. the record that lists the id in `former_ids` (one record; its kind
    #      variant of the id's kind, else the collision rule);
    #   2. failing that, the make's new slug (make `former_slugs`): the same
    #      model slug under it, exactly or through ITS former ids.
    def successor_of(id)
      found = absorbed(id)
      return found if found

      kind, make_slug, model_slug = id.to_s.split("/", 3)
      return nil unless model_slug && (make = make_by_former_slug(make_slug))

      moved = "#{kind}/#{make.slug}/#{model_slug}"
      models_by_id(moved).first || absorbed(moved)
    end

    private

    def absorbed(id)
      hits = models_by_former_id(id)
      return nil if hits.empty? || hits.map { |m| [m.make_slug, m.model_slug] }.uniq.size > 1

      kind = id.to_s.split("/", 2).first
      hits.find { |m| m.kind.to_s == kind } || KindRule.pick(hits)
    end

    # Built once on first use; arrays keep dataset order.
    def resolution_index
      @resolution_index ||= begin
        idx = { id: {}, former_id: {}, alias: {}, name: {} }
        all_models.each { |m| index_model(idx, m) }
        idx.each_value(&:freeze).freeze
      end
    end

    def index_model(idx, model)
      record = "#{model.make_slug}/#{model.model_slug}"
      (idx[:id]["#{model.kind}/#{record}"] ||= []) << model
      model.former_ids.each { |f| (idx[:former_id][f] ||= []) << model }
      model.aliases.each do |a|
        key = Vehicles.normalize(a)
        (idx[:alias][key] ||= []) << model unless key.empty?
      end
      (idx[:name][Vehicles.normalize(model.name)] ||= []) << record
    end
  end
end
