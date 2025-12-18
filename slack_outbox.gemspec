# frozen_string_literal: true

require_relative "lib/slack_outbox/version"

Gem::Specification.new do |spec|
  spec.name = "slack_outbox"
  spec.version = SlackOutbox::VERSION
  spec.authors = ["Kali Donovan"]
  spec.email = ["kali@teamshares.com"]

  spec.summary = "Slack notification outbox using Axn actions"
  spec.description = "Extracted Slack notification functionality with support for multiple workspaces and channels"
  spec.homepage = "https://github.com/teamshares/slack_outbox"
  spec.required_ruby_version = ">= 3.1.0"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/teamshares/slack_outbox/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "axn"
  spec.add_dependency "slack-ruby-client"

  spec.add_development_dependency "rspec", "~> 3.0"
end
