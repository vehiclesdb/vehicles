# frozen_string_literal: true

require "test_helper"

module Vehicles
  # The one kind-collision rule (vehiclesdb RESOLUTION.md §3; DECISIONS D1):
  # the unhinted cases every surface must answer alike, on the bundled data.
  class KindRuleTest < TestCase
    def test_unhinted_text_and_pairs
      assert_equal "van/iveco/daily", Vehicles.identify("iveco daily").model.id
      assert_equal "van/mercedes-benz/sprinter", Vehicles.match_model("Mercedes-Benz", "Sprinter").model.id
      assert_equal "van/volkswagen/caddy", Vehicles.match_model("Volkswagen", "Caddy").model.id
      assert_equal "car/mercedes-benz/v-class", Vehicles.match_model("Mercedes-Benz", "V-Class").model.id
      assert_equal "moped/yamaha/aerox", Vehicles.identify("yamaha aerox").model.id
      assert_equal "van/iveco/daily", Vehicles.match_model("Iveco", "35S14").model.id # a form on van + truck
    end

    def test_a_collision_is_not_ambiguous
      m = Vehicles.match_model("Iveco", "Daily")

      refute_predicate m, :ambiguous?
      assert_equal %i[bus truck van], m.candidates.map(&:kind).sort
    end

    def test_kinds_versus_kind_on_an_id
      assert_nil Vehicles.identify("bus/iveco/daily", kinds: ["car"])
      assert_equal "bus/iveco/daily", Vehicles.identify("bus/iveco/daily", kind: "car").model.id
      assert_nil Vehicles.identify("iveco daily", kinds: [])
    end

    def test_the_order_after_mass_decile
      models = %i[motorcycle moped truck bus car van].map do |k|
        Struct.new(:kind, :mass_decile, :id).new(k, 1, "#{k}/x/y")
      end

      assert_equal(%i[van car bus truck moped motorcycle],
                   (1..6).map { KindRule.pick(models).kind.tap { |k| models.reject! { |m| m.kind == k } } })
    end
  end
end
