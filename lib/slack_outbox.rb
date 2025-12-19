# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "slack-ruby-client"
begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is optional for runtime, only needed for async operations
end
require "axn"
require_relative "slack_outbox/version"
require_relative "slack_outbox/configuration"

module SlackOutbox
  class Error < StandardError; end
end

require_relative "slack_outbox/profile"
require_relative "slack_outbox/profile_registry"
require_relative "slack_outbox/delivery_axn"
require_relative "slack_outbox/file_wrapper"
require_relative "slack_outbox/multi_file_wrapper"

module SlackOutbox
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
      raise Error, "No default profile set. Call SlackOutbox.register(...) first"
    end

    def deliver(**) = default_profile.deliver(**)
    def deliver!(**) = default_profile.deliver!(**)
  end
end
