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
    def register_profile(name, config)
      ProfileRegistry.register(name, config)
    end

    def profile(name)
      ProfileRegistry.find(name)
    end

    def default_profile
      ProfileRegistry.default_profile
    end

    def default_profile=(name)
      ProfileRegistry.default_profile = name
    end

    def deliver(**kwargs) # rubocop:disable Naming/PredicateMethod
      if kwargs[:files].present?
        multi_file_wrapper = MultiFileWrapper.new(kwargs[:files])
        max_size = config.max_background_file_size
        if max_size && multi_file_wrapper.total_file_size > max_size
          raise Error, "Total file size (#{multi_file_wrapper.total_file_size} bytes) exceeds configured limit (#{max_size} bytes) for background jobs"
        end
      end
      DeliveryAxn.call_async(profile: default_profile, **kwargs)
      true
    end

    def deliver!(**)
      DeliveryAxn.call!(profile: default_profile, **).thread_ts
    end
  end
end
