# frozen_string_literal: true

module SlackOutbox
  class Profile
    attr_reader :token, :dev_channel, :error_channel, :channels, :user_groups, :slack_client_config

    def initialize(token:, dev_channel: nil, error_channel: nil, channels: {}, user_groups: {}, slack_client_config: {})
      @token = token
      @dev_channel = dev_channel
      @error_channel = error_channel
      @channels = channels.freeze
      @user_groups = user_groups.freeze
      @slack_client_config = slack_client_config.freeze
    end

    def deliver(**) # rubocop:disable Naming/PredicateMethod
      DeliveryAxn.call_async(profile: self, **)
      true
    end

    def deliver!(**)
      DeliveryAxn.call!(profile: self, **).thread_ts
    end
  end
end
