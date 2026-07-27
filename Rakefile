# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Scope RuboCop to this gem's own code. CI (bundler-cache) installs gems into an
# in-repo vendor/bundle, and a dependency's own .rubocop.yml — slack-ruby-client's
# `require`s rubocop-performance/-rake/-rspec — would otherwise be read during target
# scanning and crash on those absent plugins. Linting vendored gems is never intended.
RuboCop::RakeTask.new do |task|
  task.patterns = %w[lib spec bin Rakefile Gemfile slack_sender.gemspec]
end

task default: %i[spec rubocop]

# Require default to pass before release. This relies on the default gem release task
# (from bundler/gem_tasks) depending on "build"; default runs before build, so before push.
Rake::Task["build"].enhance([:default])
