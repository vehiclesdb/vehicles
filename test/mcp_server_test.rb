# frozen_string_literal: true

require "test_helper"
require "vehicles/mcp_server"
require "stringio"

module Vehicles
  # Drives the MCP server through its stdio transport with in-memory pipes —
  # the same JSON-RPC frames a real agent host sends.
  class McpServerTest < TestCase
    def rpc(*messages)
      input  = StringIO.new("#{messages.map(&:to_json).join("\n")}\n")
      output = StringIO.new
      McpServer.new(input: input, output: output).run
      output.string.each_line.map { |l| JSON.parse(l) }
    end

    def call_tool(name, arguments)
      res = rpc({ jsonrpc: "2.0", id: 1, method: "tools/call",
                  params: { name: name, arguments: arguments } }).first

      refute res.dig("result", "isError"), "tool errored: #{res}"
      JSON.parse(res.dig("result", "content", 0, "text"))
    end

    def test_initialize_handshake
      res = rpc({ jsonrpc: "2.0", id: 0, method: "initialize", params: {} }).first

      assert_equal "vehicles", res.dig("result", "serverInfo", "name")
      assert res.dig("result", "capabilities").key?("tools")
    end

    def test_tools_list_exposes_the_four_tools
      res = rpc({ jsonrpc: "2.0", id: 1, method: "tools/list" }).first
      names = res.dig("result", "tools").map { |t| t["name"] }

      assert_equal %w[search_makes search_models get_model top_models], names
    end

    def test_search_makes_resolves_aliases
      data = call_tool("search_makes", { "query" => "vw" })

      assert(data["makes"].any? { |m| m["slug"] == "volkswagen" })
    end

    def test_search_models_ranks_exact_first
      data = call_tool("search_models", { "query" => "golf", "limit" => 5 })

      assert_equal "Golf", data["models"].first["model"]
      assert_equal "Volkswagen", data["models"].first["make"]
    end

    def test_get_model_returns_the_full_record
      data = call_tool("get_model", { "make" => "vw", "model" => "golf" })

      assert_equal "volkswagen-golf", data["slug"]
      assert_includes data["available_in"], "nl"
      assert_kind_of Integer, data["global_popularity_decile"]
    end

    def test_get_model_miss_hints_instead_of_erroring
      data = call_tool("get_model", { "make" => "nope", "model" => "nothing" })

      refute data["found"]
      assert_match(/search_models/, data["hint"])
    end

    def test_top_models_filters_by_kind_and_country
      data = call_tool("top_models", { "kind" => "car", "country" => "nl", "limit" => 3 })

      assert_equal 3, data["models"].size
      assert(data["models"].all? { |m| m["kind"] == "car" && m["available_in"].include?("nl") })
    end

    def test_unknown_method_errors_and_parse_errors_do_not_kill_the_loop
      out = rpc({ jsonrpc: "2.0", id: 9, method: "bogus/method" })

      assert_equal(-32_601, out.first.dig("error", "code"))

      input  = StringIO.new("this is not json\n#{{ jsonrpc: "2.0", id: 1, method: "ping" }.to_json}\n")
      output = StringIO.new
      McpServer.new(input: input, output: output).run
      lines = output.string.each_line.map { |l| JSON.parse(l) }

      assert_equal(-32_700, lines.first.dig("error", "code"))
      assert_equal({}, lines.last["result"], "the ping after the garbage line must still answer")
    end
  end
end
