# frozen_string_literal: true

require_relative "lib/slack_outbox/version"

Gem::Specification.new do |spec|
  spec.name = "slack_outbox"
  spec.version = SlackOutbox::VERSION
  spec.authors = ["Kali Donovan"]
  spec.email = ["kali@teamshares.com"]

  spec.summary = "Slack notification outbox using Axn actions"
  spec.description = "Slack notification functionality with support for multiple workspaces and channels"
  spec.homepage = "https://github.com/teamshares/slack_outbox"
  spec.license = "MIT"

  # NOTE: uses endless methods from 3, literal value omission from 3.1, and Axn which requires 3.2.1+
  spec.required_ruby_version = ">= 3.2.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/teamshares/slack_outbox/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile Gemfile.lock .rspec_status pkg/ node_modules/ tmp/ .rspec .rubocop
                          .tool-versions package.json])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "axn", "0.1.0-alpha.3"
  spec.add_dependency "slack-ruby-client"
end
