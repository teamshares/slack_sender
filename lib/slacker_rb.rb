# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/concern"
require "slack-ruby-client"
begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is optional for runtime, only needed for async operations
end
begin
  require "active_job"
rescue LoadError
  # ActiveJob is optional for runtime, only needed for async operations
end
require "axn"
require_relative "slacker_rb/version"
require_relative "slacker_rb/configuration"
require_relative "slacker_rb/util"

module Slacker
  class Error < StandardError; end
end

require_relative "slacker_rb/profile"
require_relative "slacker_rb/profile_registry"
require_relative "slacker_rb/delivery_axn"
require_relative "slacker_rb/file_wrapper"
require_relative "slacker_rb/multi_file_wrapper"

module Slacker
  class << self
    def register(name = nil, **config)
      ProfileRegistry.register(name.presence || :default, config)
    end

    def profile(name)
      ProfileRegistry.find(name)
    end

    def default_profile
      ProfileRegistry.find(:default)
    rescue ProfileNotFound
      raise Error, "No default profile set. Call Slacker.register(...) first"
    end

    def call(**) = default_profile.call(**)
    def call!(**) = default_profile.call!(**)
    def format_group_mention(key) = default_profile.format_group_mention(key)
  end
end
