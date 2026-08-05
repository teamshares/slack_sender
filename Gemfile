# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in slacker-rb.gemspec
gemspec

# Development dependencies
gem "factory_bot", "~> 6.0"
gem "rspec", "~> 3.0"
gem "sidekiq"

# Misc/default
# csv is used in specs (CSV.generate); no longer a default gem as of Ruby 3.4, so declare it.
gem "csv", "~> 3.3"
gem "irb"
gem "lefthook", "~> 2.0" # Git-hook manager (pre-commit RuboCop on staged files)
gem "rake", "~> 13.0"
# Match Ruby default gem to avoid "already initialized constant" warnings
gem "rdoc", "~> 7.2"
gem "rubocop", "~> 1.21"
