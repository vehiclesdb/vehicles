# frozen_string_literal: true

require "test_helper"
require "json"

module Vehicles
  # Runs the cross-surface resolution contract's executable form
  # (vehiclesdb RESOLUTION.md §6, `conformance/resolve.json`, copied to
  # test/fixtures/conformance/resolve.json) against the dataset the gem ships.
  # Every VehiclesDB surface (gem, API, widget, SDKs) runs the same cases, so a
  # failure here means the gem disagrees with the others — fix the gem, or
  # update the case in the data repo with the reason.
  #
  # Case shape: { entry: "pair"|"text", make, model (pair) | input (text),
  # kind, expect: id | null | "ambiguous", method, min_dataset }. Cases whose
  # min_dataset is newer than the data in effect are skipped (they need data
  # this snapshot does not carry yet). Set VEHICLES_CONFORMANCE_DATA to a
  # dist file to run them against another snapshot.
  class ResolutionConformanceTest < TestCase
    CASES = File.expand_path("fixtures/conformance/resolve.json", __dir__)

    def setup
      skip "no conformance file at #{CASES}" unless File.exist?(CASES)
      Vehicles.data_path = ENV["VEHICLES_CONFORMANCE_DATA"] if ENV["VEHICLES_CONFORMANCE_DATA"]
    end

    def test_every_applicable_case
      raw = JSON.parse(File.read(CASES))
      cases = raw.is_a?(Hash) ? raw.fetch("cases") : raw
      applicable = cases.select { |c| applicable?(c) }
      skip "no case applies to dataset #{Vehicles.data_version}" if applicable.empty?

      applicable.each { |c| check(c) }
    end

    private

    def applicable?(kase)
      min = kase["min_dataset"]
      min.nil? || Gem::Version.new(min) <= Gem::Version.new(Vehicles.data_version.to_s)
    end

    def check(kase)
      got = resolve(kase)
      label = "#{kase["entry"]} #{(kase["input"] || [kase["make"], kase["model"]]).inspect} " \
              "kind=#{kase["kind"].inspect} kinds=#{kase["kinds"].inspect} #{kase["note"]}".strip

      assert_outcome(kase["expect"], got, label)
      return unless kase["method"] && got

      assert_equal kase["method"], got.rung.to_s, "#{label}: method"
    end

    def resolve(kase)
      kind = kase["kind"]&.to_sym
      case kase["entry"]
      when "pair" then Vehicles.match_model(kase["make"], kase["model"], kind: kind, kinds: kase["kinds"])
      when "text" then Vehicles.identify(kase["input"], kind: kind, kinds: kase["kinds"])

      else flunk "unknown entry #{kase["entry"].inspect}"
      end
    end

    def assert_outcome(expect, got, label)
      case expect
      when nil then assert_nil got, "#{label}: expected no match"
      when "ambiguous" then assert_predicate got, :ambiguous?, "#{label}: expected ambiguous, got #{got.inspect}"
      else
        model = got&.model

        assert_equal expect, model && "#{model.kind}/#{model.make_slug}/#{model.model_slug}", label
      end
    end
  end
end
