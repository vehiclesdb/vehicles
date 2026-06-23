# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in vehicles.gemspec
gemspec

gem "rake", "~> 13.0"

group :development, :test do
  gem "appraisal"
  gem "minitest"
  gem "mocha", "~> 2.0"
  gem "simplecov", require: false
  # Rails is a soft runtime dependency (the gem works without it). The base
  # Gemfile only needs ActiveModel to exercise the validators; the Appraisals
  # layer the specific full-Rails versions on top (don't declare `rails` here, or
  # it conflicts with each appraisal's `gem "rails", "~> X"`).
  gem "activemodel", ">= 7.0", "< 9.0"
  # Ruby 4.0+ compatibility: ostruct was removed from stdlib.
  gem "ostruct"
end

group :development do
  gem "rubocop", "~> 1.0"
  gem "rubocop-minitest", "~> 0.35"
  gem "rubocop-performance", "~> 1.0"
end
