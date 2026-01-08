# frozen_string_literal: true

module SlackSender
  class Profile
    attr_reader :dev_channel, :dev_user_group, :error_channel, :channels, :user_groups, :slack_client_config, :dev_channel_redirect_prefix, :key

    def initialize(key:, token:, dev_channel: nil, dev_user_group: nil, error_channel: nil, channels: {}, user_groups: {}, slack_client_config: {},
                   dev_channel_redirect_prefix: nil)
      @key = key
      @token = token
      @dev_channel = dev_channel
      @dev_user_group = dev_user_group
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
      raise Error, "can't upload files to background job... yet (feature planned post alpha release)" if kwargs[:files].present?

      unless ProfileRegistry.all[key] == self
        raise Error,
              "Profile must be registered before using async delivery. Register it with SlackSender.register(name, config)"
      end

      DeliveryAxn.call_async(profile: key.to_s, **kwargs)
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

      group_id = dev_user_group if dev_user_group.present? && !SlackSender.config.in_production?

      ::Slack::Messages::Formatting.group_link(group_id)
    end

    def token
      @profile_token ||= @token.respond_to?(:call) ? @token.call : @token
    end

    private

    def preprocess_call_kwargs(raw)
      raw.dup.tap do |kwargs|
        validate_and_handle_profile_parameter!(kwargs)
        preprocess_channel!(kwargs)
        preprocess_blocks_and_attachments!(kwargs)
      end
    end

    def validate_and_handle_profile_parameter!(kwargs)
      return unless kwargs.key?(:profile)

      is_registered = ProfileRegistry.all[key] == self
      registered_name_sym = is_registered ? key.to_sym : nil
      requested_profile = kwargs[:profile]

      # Normalize for comparison (handle both symbol and string)
      requested_profile_sym = requested_profile.to_sym

      if registered_name_sym == :default
        # Default profile: allow profile parameter to override (keep it in kwargs, convert to string for consistency)
        # This enables SlackSender.call(profile: :foo) to work
        kwargs[:profile] = requested_profile_sym.to_s
      elsif registered_name_sym.nil?
        # Unregistered profile: still validate to prevent confusion
        raise ArgumentError,
              "Cannot specify profile: :#{requested_profile_sym} when calling on unregistered profile. " \
              "Register the profile first with SlackSender.register(name, config)"
      elsif registered_name_sym == requested_profile_sym
        # Non-default profile with matching profile parameter: strip it out (redundant)
        kwargs.delete(:profile)
      else
        # Non-default profile with non-matching profile parameter: raise error
        raise ArgumentError,
              "Cannot specify profile: :#{requested_profile_sym} when calling on profile :#{registered_name_sym}. " \
              "Use SlackSender.profile(:#{requested_profile_sym}).call(...) instead"
      end
    end

    def preprocess_channel!(kwargs)
      # User-facing interface uses symbol to indicate "known channel" and string for
      # "arbitrary value - pass through unchecked". But internal interface passes to sidekiq,
      # so the DeliveryAxn accepts "should validate" as a separate argument.
      return unless kwargs[:channel].is_a?(Symbol)

      kwargs[:channel] = kwargs[:channel].to_s
      kwargs[:validate_known_channel] = true
    end

    def preprocess_blocks_and_attachments!(kwargs)
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
