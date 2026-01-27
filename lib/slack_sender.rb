# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/keys"
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
require_relative "slack_sender/version"
require_relative "slack_sender/configuration"
require_relative "slack_sender/util"
require_relative "slack_sender/error_messages"

module SlackSender
  class Error < StandardError; end

  # Raised for invalid arguments that should not be retried
  # (e.g., missing content, invalid blocks, incompatible options)
  class InvalidArgumentsError < Error; end
end

require_relative "slack_sender/profile"
require_relative "slack_sender/profile_registry"
require_relative "slack_sender/delivery_axn"
require_relative "slack_sender/file_wrapper"
require_relative "slack_sender/multi_file_wrapper"

module SlackSender
  class << self
    def register(name = nil, **config)
      ProfileRegistry.register(name.presence || :default, config)
    end

    def profile(name)
      ProfileRegistry.find(name)
    end

    def [](name) = profile(name)

    def default_profile
      ProfileRegistry.find(:default)
    rescue ProfileNotFound
      raise Error, "No default profile set. Call SlackSender.register(...) first"
    end

    def call(**) = default_profile.call(**)
    def call!(**) = default_profile.call!(**)
    def format_group_mention(key) = default_profile.format_group_mention(key)
  end
end
