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

  # axn: a terse convention for business logic. Lower bound is 0.1.0-alpha.5: the first published
  # version where a Proc `default:` is dynamic on its own (the `callable:` kwarg was removed), which
  # `configuration.rb`'s `sandbox_mode` relies on. It also carries the Axn::Configurable namespaced
  # config (PRO-2880) and DSL-generated predicate readers (PRO-2888) the gem uses.
  spec.add_dependency "axn", ">= 0.1.0-alpha.5", "< 0.2.0"
  # slack-ruby-client >= 2.7: DeliveryAxn#upload_files_v2 calls `files_upload_v2(files: [...])`
  # with the Array form, which was added in 2.7.0 (PR #567). Earlier versions only accept a single
  # file via `filename:`/`content:` and would raise on the `files:` array. Upper bound `< 4` caps
  # the next major (currently 3.x) so a breaking release can't resolve unvetted.
  spec.add_dependency "slack-ruby-client", ">= 2.7", "< 4"
end
