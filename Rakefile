# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Require default to pass before release. This relies on the default gem release task
# (from bundler/gem_tasks) depending on "build"; default runs before build, so before push.
Rake::Task["build"].enhance([:default])
