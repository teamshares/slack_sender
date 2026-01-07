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

    def call(**)
      return false unless SlackSender.config.enabled

      kwargs = preprocess_call_kwargs(**)

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

      kwargs = preprocess_call_kwargs(**)
      DeliveryAxn.call!(profile: self, **kwargs).thread_ts
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

    private

    def preprocess_call_kwargs(raw)
      raw.dup.tap do |kwargs|
        # User-facing interface uses symbol to indicate "known channel" and string for
        # "arbitrary value - pass through unchecked". But internal interface passes to sidekiq,
        # so the DeliveryAxn accepts "should validate" as a separate argument.
        if kwargs[:channel].is_a?(Symbol)
          kwargs[:channel] = kwargs[:channel].to_s
          kwargs[:validate_known_channel] = true
        end

        # Convert symbol keys to strings in blocks and attachments for JSON serialization
        # This ensures they're serializable for async jobs (Sidekiq/ActiveJob)
        if kwargs[:blocks].present?
          kwargs[:blocks] = deep_stringify_keys(kwargs[:blocks])
        else
          kwargs.delete(:blocks)
        end

        if kwargs[:attachments].present?
          kwargs[:attachments] = deep_stringify_keys(kwargs[:attachments])
        else
          kwargs.delete(:attachments)
        end
      end
    end

    # Deep convert hash keys from symbols to strings for JSON serialization
    # Uses ActiveSupport's deep_stringify_keys for hashes, and handles arrays recursively
    def deep_stringify_keys(value)
      case value
      when Array
        value.map { |item| deep_stringify_keys(item) }
      when Hash
        value.deep_stringify_keys
      else
        value
      end
    end
  end
end
