# frozen_string_literal: true

require "test_helper"

module Vehicles
  # Typo tolerance is for HUMAN-typed names only. Id-, path- and slug-shaped
  # input must resolve exactly or not at all — never to a guessed make
  # (web-session requirement, 0.7.8): web routes (/makes/:slug), API ids
  # (car/make/model) and the MCP tools depend on it.
  class IdShapedInputTest < TestCase
    def test_slug_shaped_typos_never_fuzz
      assert_nil Vehicles.make("marcedes-benz")
      assert_equal "mercedes-benz", Vehicles.make("mercedes-benz")&.slug, "an exact slug still resolves"
    end

    def test_id_and_path_shaped_typos_return_nil
      assert_nil Vehicles.find("marcedes-benz/c-class")
      assert_nil Vehicles.find("car/marcedes-benz/c-class")
      assert_nil Vehicles.make("/makes/marcedes")
      assert_nil Vehicles.make("makes/marcedes")
    end

    def test_other_machine_shapes_never_fuzz
      # Verifier finding (0.7.8 delta): each of these fuzzed for every typo.
      [:marcedes, :marcedes_benz, "marcedes_benz", "Marcedes_Benz", "MARCEDES-BENZ",
       "marcedes-benz-", "-marcedes-benz", "marcedes+benz", "marcedes--benz"].each do |q|
        assert_nil Vehicles.make(q), "#{q.inspect} must not fuzz"
      end
      assert_nil Vehicles.find("MARCEDES-BENZ-C-CLASS")
      assert_nil Vehicles.find("marcedes_benz_c_class")
      assert_nil Vehicles.find(:marcedes_benz_c_class)
      assert_nil Vehicles.model("MARCEDES-BENZ", "c-class")
      assert_empty Vehicles.models(:marcedes_benz)
      assert_equal "mercedes-benz", Vehicles.make(:mercedes)&.slug, "exact Symbol input still resolves"
    end

    def test_human_typed_names_still_fuzz
      assert_equal "mercedes-benz", Vehicles.make("marcedes")&.slug
      assert_equal "mercedes-benz", Vehicles.make("Marcedes-Benz")&.slug, "mixed case = typed by a person"
      assert_equal "mercedes-benz", Vehicles.find("marcedes c-class")&.make_slug
    end

    def test_mcp_tools_are_exact
      server = McpServer.new

      assert_equal 0, server.send(:search_makes, { "query" => "marcedes" })[:total], "no fuzzy make injected"
      refute server.send(:get_model, { "make" => "marcedes", "model" => "sprinter" })[:found]
      assert_equal "Sprinter", server.send(:get_model, { "make" => "mercedes-benz", "model" => "sprinter" })[:model]
    end
  end
end
