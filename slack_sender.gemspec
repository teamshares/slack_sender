# frozen_string_literal: true

require_relative "lib/slack_sender/version"

Gem::Specification.new do |spec|
  spec.name = "slack_sender"
  spec.version = SlackSender::VERSION
  spec.authors = ["Kali Donovan"]
  spec.email = ["kali@teamshares.com"]

  spec.summary = "Slack messages for people who don’t want to babysit Slack."
  spec.description = "Slack messaging with background dispatch with automatic rate-limit retries."
  spec.homepage = "https://github.com/teamshares/slack_sender"
  spec.license = "MIT"

  # NOTE: uses endless methods from 3, literal value omission from 3.1, and Axn which requires 3.2.1+
  spec.required_ruby_version = ">= 3.2.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/teamshares/slack_sender/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship the runtime payload only — allowlist, not denylist. A gem's shippable surface is small and
  # stable (lib/ + a few root docs), so enumerating it beats an ever-growing exclude list that
  # silently leaks new dev artifacts (docs site, editor config, tool configs) into the package.
  # `git ls-files` keeps this to tracked files. Anything not listed here (bin/, spec/, docs/,
  # internal-docs/, .github/, lefthook.yml, .rubocop.yml, …) simply never ships.
  spec.files = IO.popen(
    %w[git ls-files -z -- lib README.md CHANGELOG.md],
    chdir: __dir__, err: IO::NULL,
  ) { |ls| ls.readlines("\x0", chomp: true) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # axn: a terse convention for business logic. Lower bound is 0.1.0-alpha.4.3, the first version
  # to define Axn::Configurable (PRO-2769), which lib/slack_sender/configuration.rb references at
  # require time — earlier versions would NameError on load. See the Gemfile's temporary main pin.
  spec.add_dependency "axn", ">= 0.1.0-alpha.4.3", "< 0.2.0"
  spec.add_dependency "slack-ruby-client"
end
