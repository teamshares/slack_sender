# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in slacker-rb.gemspec
gemspec

# PRO-2775: temporarily pin axn to main now that the Axn::Configurable DSL (PRO-2769) is merged.
# Flip back to the released gem once that change ships in a published version.
gem "axn", github: "teamshares/axn", branch: "main"

# Development dependencies
gem "factory_bot", "~> 6.0"
gem "rspec", "~> 3.0"
gem "sidekiq"

# Misc/default
gem "irb"
gem "lefthook", "~> 2.0" # Git-hook manager (pre-commit RuboCop on staged files)
gem "rake", "~> 13.0"
# Match Ruby default gem to avoid "already initialized constant" warnings
gem "rdoc", "~> 7.2"
gem "rubocop", "~> 1.21"
