# frozen_string_literal: true

# SimpleCov configuration file (auto-loaded before test suite)
# This keeps test_helper.rb clean and follows best practices

SimpleCov.start do
  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter

  add_filter "/test/"

  # Track Ruby files in lib directory
  track_files "lib/**/*.rb"

  # The hosted-API provider's network path can't run without a live server, so
  # its HTTP plumbing is excluded from coverage (the seam itself is tested).
  add_filter "lib/vehicles/providers/hosted_provider.rb"

  # Rails-boot-time infrastructure (the Railtie initializer and the install
  # generator) is exercised by Rails/the generator at runtime, not by unit tests.
  add_filter "lib/vehicles/railtie.rb"
  add_filter "lib/generators"

  enable_coverage :branch

  minimum_coverage line: 90, branch: 75

  command_name "Job #{ENV["TEST_ENV_NUMBER"]}" if ENV["TEST_ENV_NUMBER"]
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "\n#{"=" * 60}"
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  branch_coverage = SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || "N/A"
  puts "Branch Coverage: #{branch_coverage}%"
  puts "=" * 60
end
