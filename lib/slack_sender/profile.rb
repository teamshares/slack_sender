# frozen_string_literal: true

module SlackSender
  class Profile
    attr_reader :dev_channel, :error_channel, :channels, :user_groups, :slack_client_config, :dev_channel_redirect_prefix

    def initialize(token:, dev_channel: nil, error_channel: nil, channels: {}, user_groups: {}, slack_client_config: {}, dev_channel_redirect_prefix: nil)
      @token = token
      @dev_channel = dev_channel
      @error_channel = error_channel
      @channels = channels.freeze
      @user_groups = user_groups.freeze
      @slack_client_config = slack_client_config.freeze
      @dev_channel_redirect_prefix = dev_channel_redirect_prefix
    end

    def call(**kwargs)
      return false unless SlackSender.config.enabled

      # Validate async backend is configured and available
      unless SlackSender.config.async_backend_available?
        raise Error,
              "No async backend configured. Use SlackSender.call! to execute inline, " \
              "or configure an async backend (sidekiq or active_job) via " \
              "SlackSender.config.async_backend to enable automatic retries for failed Slack sends."
      end

      # Only relevant before we send to the backend -- avoid filling redis with large files
      if kwargs[:files].present?
        total_file_size = MultiFileWrapper.new(kwargs[:files]).total_file_size
        max_size = SlackSender.config.max_background_file_size

        if max_size && total_file_size > max_size
          raise Error, "Total file size (#{total_file_size} bytes) exceeds configured limit (#{max_size} bytes) for background jobs"
        end
      end

      registered_name = instance_variable_get(:@registered_name)
      raise Error, "Profile must be registered before using async delivery. Register it with SlackSender.register(name, config)" unless registered_name

      DeliveryAxn.call_async(profile: registered_name.to_s, **kwargs)
      true
    end

    def call!(**)
      return false unless SlackSender.config.enabled

      DeliveryAxn.call!(profile: self, **).thread_ts
    end

    def format_group_mention(key)
      group_id = if key.is_a?(Symbol)
                   user_groups[key] || raise("Unknown user group: #{key}")
                 else
                   key
                 end

      group_id = user_groups[:slack_development] unless SlackSender.config.in_production?

      ::Slack::Messages::Formatting.group_link(group_id)
    end

    def token
      @profile_token ||= @token.respond_to?(:call) ? @token.call : @token
    end
  end
end
