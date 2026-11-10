# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Vehicles
  # Vehicles.dataset_slice: the catalog scope as dist/vehicles.json records,
  # for the widget's `data` option and the SDKs' dataset mode.
  class DatasetSliceTest < TestCase
    def slice = Vehicles.dataset_slice(kind: :car, country: :es)

    def test_slice_carries_the_release_header_and_licence
      s = slice

      assert_equal Vehicles.data_version, s["version"]
      assert_equal %w[car], s["kinds"]
      assert_equal "CC-BY-4.0", s["license"]
      assert_equal "https://vehiclesdb.com", s.dig("attribution", "url")
    end

    def test_slice_is_the_catalog_scope_in_the_dist_shape
      s = slice
      catalog = Vehicles.catalog(kind: :car, country: :es)

      assert_equal(catalog.keys, s["makes"].map { |m| m["name"] })
      s["makes"].each do |make|
        assert_kind_of String, make["slug"]
        assert_equal %w[car], make["kinds"]
        assert_equal catalog[make["name"]].sort, make["models"].map { |m| m["name"] }.uniq.sort
      end
    end

    def test_models_keep_what_resolution_reads_and_project_the_country
      models = slice["makes"].flat_map { |m| m["models"] }

      models.each do |m|
        assert_equal "car", m["kind"]
        assert_equal %w[es], m["availability"]
        assert_empty m.keys - %w[name slug kind aliases forms former_ids global_decile mass_decile
                                 availability country_ranks registration_years]
        assert_empty (m["country_ranks"] || {}).keys - %w[es]
      end
      assert(models.none? { |m| m.key?("regions") || m.key?("body_type") })
    end

    def test_optional_resolution_keys_survive
      models = slice["makes"].flat_map { |m| m["models"] }

      %w[aliases forms former_ids country_ranks mass_decile].each do |key|
        assert models.any? { |m| m[key] }, "no record carries #{key}"
      end
    end

    def test_without_a_country_records_keep_every_country
      golf = Vehicles.dataset_slice(kind: :car)["makes"].find { |m| m["slug"] == "volkswagen" }["models"]
                     .find { |m| m["slug"] == "golf" }

      assert_operator golf["availability"].size, :>, 1
      assert_operator golf["country_ranks"].size, :>, 1
    end

    def test_kinds_is_a_hard_filter
      s = Vehicles.dataset_slice(kinds: %i[car van], country: :es)

      assert_equal %w[car van], s["kinds"]
      assert_equal %w[car van], s["makes"].flat_map { |m| m["models"].map { |x| x["kind"] } }.uniq.sort
      assert_empty Vehicles.dataset_slice(kinds: [])["makes"]
      assert_equal %w[bus car moped motorcycle truck van], Vehicles.dataset_slice["kinds"]
    end

    # The slice is a dataset: read back, it resolves and ids exactly as the
    # full release does for every record in scope.
    def test_slice_reads_back_as_a_dataset_with_the_same_ids
      full = Vehicles.dataset_slice(kind: :car, country: :es)["makes"].to_h do |make|
        [make["slug"], make["models"].map { |m| [m["name"], Vehicles.model(make["name"], m["name"], kind: :car).id] }]
      end
      Dir.mktmpdir do |dir|
        path = File.join(dir, "vehicles.json")
        File.write(path, JSON.generate(slice))
        Vehicles.data_path = path

        assert_equal Vehicles.catalog(kind: :car, country: :es).keys, Vehicles.catalog.keys
        full.each do |make_slug, pairs|
          pairs.each do |name, id|
            assert_equal id, Vehicles.model(make_slug, name, kind: :car)&.id, "#{make_slug} #{name}"
          end
        end
      end
    end
  end
end
