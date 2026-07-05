# frozen_string_literal: true

require "json"

module Vehicles
  # A tiny, read-only MCP (Model Context Protocol) server over the bundled
  # dataset — so agents and LLM apps can ground themselves in real vehicle
  # data instead of hallucinating nameplates. Runs on stdio, speaks JSON-RPC
  # 2.0, needs no network, no API key, no database: `vehicles-mcp` and done.
  #
  #   { "mcpServers": { "vehicles": { "command": "vehicles-mcp" } } }
  #
  # Design notes:
  #   * stdlib-only, like the rest of the gem (JSON over $stdin/$stdout).
  #   * Read-only by construction — there is no tool that mutates anything.
  #   * Answers come from the same snapshot the gem serves your app, so an
  #     agent and your UI can never disagree about what exists.
  #   * Protocol: newline-delimited JSON-RPC per the MCP stdio transport.
  #     We answer `initialize`, `ping`, `tools/list`, `tools/call`, and
  #     ignore notifications — the minimum a well-behaved server needs.
  class McpServer
    PROTOCOL_VERSION = "2025-06-18"

    # Tool definitions, MCP-shaped. Descriptions are written for the MODEL
    # reading them (what to call, when, and what comes back), not for humans.
    TOOLS = [
      {
        name: "search_makes",
        description: "Search vehicle manufacturers (makes) by name. Returns matching makes " \
                     "with their slug and which vehicle kinds they produce (car, motorcycle, " \
                     "moped, van, truck, bus). Call with an empty query to list every make. " \
                     "Forgiving: 'vw', 'merc' and 'škoda' resolve.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Make name or fragment (empty = all makes)" },
            kind: { type: "string", enum: %w[car motorcycle moped van truck bus],
                    description: "Only makes producing this kind" }
          }
        }
      },
      {
        name: "search_models",
        description: "Search vehicle models by name across all makes (e.g. 'golf', 'corolla', " \
                     "'transit'). Returns ranked matches with make, kind, body type, global " \
                     "popularity decile (1 = top 10%) and the countries where the model is " \
                     "evidenced by official sources.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Model name or fragment; 'make model' works too" },
            limit: { type: "integer", description: "Max results (default 20)" }
          },
          required: ["query"]
        }
      },
      {
        name: "get_model",
        description: "Look up ONE exact vehicle model by make + model name and get its full " \
                     "record: canonical names, slugs, kind, body type, popularity decile, and " \
                     "availability countries. Use after search_models, or directly when you " \
                     "already know the pair (e.g. make: 'Toyota', model: 'Hilux').",
        inputSchema: {
          type: "object",
          properties: {
            make: { type: "string", description: "Make name, slug, or alias ('vw' works)" },
            model: { type: "string", description: "Model name or slug" }
          },
          required: %w[make model]
        }
      },
      {
        name: "top_models",
        description: "The most popular vehicle models by registration data, optionally filtered " \
                     "by kind and/or country (ISO alpha-2, e.g. 'nl', 'gb', 'th'). Popularity is " \
                     "measured from official registration/fleet counts across 12+ countries, " \
                     "expressed as deciles (1 = most popular).",
        inputSchema: {
          type: "object",
          properties: {
            kind: { type: "string", enum: %w[car motorcycle moped van truck bus] },
            country: { type: "string", description: "ISO-3166-1 alpha-2 country code" },
            limit: { type: "integer", description: "Max results (default 20)" }
          }
        }
      }
    ].freeze

    def initialize(input: $stdin, output: $stdout)
      @input = input
      @output = output
    end

    # Blocking serve loop: one JSON-RPC message per line until EOF. Malformed
    # lines get a -32700 parse error instead of killing the process — an agent
    # host restarting us mid-message must not take the server down.
    def run
      @input.each_line do |line|
        line = line.strip
        next if line.empty?

        begin
          msg = JSON.parse(line)
        rescue JSON::ParserError
          reply(id: nil, error: { code: -32_700, message: "Parse error" })
          next
        end
        handle(msg)
      end
    end

    private

    def handle(msg)
      id = msg["id"]
      case msg["method"]
      when "initialize"
        reply(id: id, result: {
                protocolVersion: PROTOCOL_VERSION,
                capabilities: { tools: {} },
                serverInfo: { name: "vehicles", version: Vehicles::VERSION,
                              title: "VehiclesDB — open vehicle makes & models" }
              })
      when "ping"
        reply(id: id, result: {})
      when "tools/list"
        reply(id: id, result: { tools: TOOLS })
      when "tools/call"
        call_tool(id, msg.dig("params", "name"), msg.dig("params", "arguments") || {})
      when nil
        reply(id: id, error: { code: -32_600, message: "Invalid request" }) if id
      else
        # Notifications (no id) are fine to ignore; unknown REQUESTS must error.
        reply(id: id, error: { code: -32_601, message: "Method not found: #{msg["method"]}" }) if id
      end
    end

    def call_tool(id, name, args)
      result =
        case name
        when "search_makes"  then search_makes(args)
        when "search_models" then search_models(args)
        when "get_model"     then get_model(args)
        when "top_models"    then top_models(args)
        else
          return reply(id: id, error: { code: -32_602, message: "Unknown tool: #{name}" })
        end
      reply(id: id, result: { content: [{ type: "text", text: JSON.pretty_generate(result) }],
                              isError: false })
    rescue StandardError => e
      # Tool-level failures are reported IN-BAND (isError), per MCP spec, so
      # the model can see what went wrong and correct its call.
      reply(id: id, result: { content: [{ type: "text", text: "Error: #{e.message}" }],
                              isError: true })
    end

    # --- the tools ------------------------------------------------------------

    def search_makes(args)
      kind = args["kind"]&.to_sym
      q = args["query"].to_s
      makes = Vehicles.dataset.makes(kind: kind)
      unless q.strip.empty?
        n = Vehicles.normalize(q)
        exact = Vehicles.dataset.find_make(q)
        makes = makes.select { |m| Vehicles.normalize(m.name).include?(n) }
        makes = [exact, *makes].uniq if exact && (kind.nil? || exact.kinds.include?(kind))
      end
      { makes: makes.map { |m| { name: m.name, slug: m.slug, kinds: m.kinds } },
        total: makes.size }
    end

    def search_models(args)
      limit = args.fetch("limit", 20).to_i.clamp(1, 100)
      hits = Vehicles.search(args.fetch("query"))
      { models: hits.first(limit).map { |m| model_json(m) },
        total: hits.size, shown: [hits.size, limit].min }
    end

    def get_model(args)
      m = Vehicles.model(args.fetch("make"), args.fetch("model")) ||
          Vehicles.find("#{args.fetch("make")} #{args.fetch("model")}")
      if m
        model_json(m)
      else
        { found: false,
          hint: "No such model. Try search_models with a fragment — " \
                "names are canonical (e.g. 'Mustang Mach-E', not 'mach e')." }
      end
    end

    def top_models(args)
      limit = args.fetch("limit", 20).to_i.clamp(1, 100)
      list = Vehicles.dataset.top_models(kind: args["kind"]&.to_sym,
                                         country: args["country"], limit: limit)
      { models: list.map { |m| model_json(m) },
        note: "Ranked by global popularity decile from official registration counts; " \
              "country filters by evidenced availability." }
    end

    def model_json(m)
      { make: m.make, model: m.name, slug: m.slug, kind: m.kind,
        body_type: m.body_type, global_popularity_decile: m.global_decile,
        available_in: m.availability }
    end

    def reply(id:, result: nil, error: nil)
      payload = { jsonrpc: "2.0", id: id }
      payload[:result] = result if result
      payload[:error]  = error if error
      @output.puts(JSON.generate(payload))
      @output.flush
    end
  end
end
