# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in slacker-rb.gemspec
gemspec

# PRO-2775: temporarily pin axn to the branch providing Axn::Configurable until it ships.
# Flip back to the released gem once that branch is merged and published.
gem "axn", github: "teamshares/axn", branch: "kali/pro-2769-axn-configuration-dsl-for-downstream-gem-consistency"

# Development dependencies
gem "factory_bot", "~> 6.0"
gem "rspec", "~> 3.0"
gem "sidekiq"

# Misc/default
gem "irb"
gem "rake", "~> 13.0"
# Match Ruby default gem to avoid "already initialized constant" warnings
gem "rdoc", "~> 7.2"
gem "rubocop", "~> 1.21"
