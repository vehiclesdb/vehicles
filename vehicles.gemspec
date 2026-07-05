# frozen_string_literal: true

require_relative "lib/vehicles/version"

Gem::Specification.new do |spec|
  spec.name    = "vehicles"
  spec.version = Vehicles::VERSION
  spec.authors = ["rameerez"]
  spec.email   = ["rubygems@rameerez.com"]

  spec.summary     = "Car makes & models for your Rails app — dropdowns, search, validation. Zero config, no API keys."
  spec.description = "vehicles ships a curated, bundled dataset of car makes and models (with kind " \
                     "and body type) and a delightful, Rails-friendly API for vehicle dropdowns, " \
                     "search, and validation. No API keys, no network calls, no database table — the " \
                     "data lives inside the gem and just works. It also acts as the SDK for the hosted " \
                     "VehiclesDB API. Code is MIT; the bundled data is CC-BY 4.0 (derived from RDW Open Data)."
  spec.homepage = "https://github.com/vehiclesdb/vehicles"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Bundle lib, the generators, and the dataset. Everything else (tests, dev
  # config, working files) is excluded — the data file is the only non-code asset.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[.aux/ .claude/ .cursor/ .git .github/ bin/ gemfiles/ test/
                          Appraisals Gemfile Rakefile .rubocop.yml .simplecov
                          .gitignore AGENTS.md CLAUDE.md context7.json])
    end
  end
  spec.require_paths = ["lib"]

  # `vehicles-mcp` — the bundled read-only MCP server (lib/vehicles/mcp_server.rb):
  # `gem install vehicles` is all it takes to give an agent grounded vehicle data.
  spec.bindir      = "exe"
  spec.executables = ["vehicles-mcp"]

  # Rails is an optional, soft dependency (detected at runtime) so the gem works
  # in plain Ruby too — hence no `add_dependency "rails"`. Dev/test deps live in
  # the Gemfile (see https://guides.rubygems.org/patterns/#runtime-vs-development-dependencies).
end
