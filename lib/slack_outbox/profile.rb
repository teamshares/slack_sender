# frozen_string_literal: true

module SlackOutbox
  class Profile
    attr_reader :token, :dev_channel, :error_channel, :channels, :user_groups, :slack_client_config, :dev_channel_redirect_prefix

    def initialize(token:, dev_channel: nil, error_channel: nil, channels: {}, user_groups: {}, slack_client_config: {}, dev_channel_redirect_prefix: nil)
      @token = token
      @dev_channel = dev_channel
      @error_channel = error_channel
      @channels = channels.freeze
      @user_groups = user_groups.freeze
      @slack_client_config = slack_client_config.freeze
      @dev_channel_redirect_prefix = dev_channel_redirect_prefix
    end

    def deliver(**kwargs) # rubocop:disable Naming/PredicateMethod
      if kwargs[:files].present?
        multi_file_wrapper = MultiFileWrapper.new(kwargs[:files])
        max_size = SlackOutbox.config.max_background_file_size
        if max_size && multi_file_wrapper.total_file_size > max_size
          raise SlackOutbox::Error,
                "Total file size (#{multi_file_wrapper.total_file_size} bytes) exceeds configured limit (#{max_size} bytes) for background jobs"
        end
      end
      DeliveryAxn.call_async(profile: self, **kwargs)
      true
    end

    def deliver!(**)
      DeliveryAxn.call!(profile: self, **).thread_ts
    end
  end
end
