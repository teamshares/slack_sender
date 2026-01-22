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
      enabled, kwargs = enabled_and_preprocessed_kwargs(**)
      return false unless enabled

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
      enabled, kwargs = enabled_and_preprocessed_kwargs(**)
      return false unless enabled

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

    def client
      @client ||= ::Slack::Web::Client.new(slack_client_config.merge(token:))
    end

    private

    def token
      return @token unless @token.respond_to?(:call)

      @memoized_token ||= @token.call
    end

    def enabled_and_preprocessed_kwargs(**)
      return [false, nil] unless SlackSender.config.enabled

      [true, preprocess_call_kwargs(**)]
    end

    def preprocess_call_kwargs(raw)
      raw.dup.tap do |kwargs|
        validate_and_handle_profile_parameter!(kwargs)
        preprocess_channel!(kwargs)
        preprocess_blocks_and_attachments!(kwargs)
      end
    end

    def validate_and_handle_profile_parameter!(kwargs)
      return unless kwargs.key?(:profile)

      registered_name_sym = registered_profile_name
      requested_profile_sym = kwargs[:profile].to_sym

      case registered_name_sym
      when :default
        handle_default_profile_parameter!(kwargs, requested_profile_sym)
      when nil
        handle_unregistered_profile_parameter!(kwargs, requested_profile_sym)
      else
        if registered_name_sym == requested_profile_sym
          handle_matching_profile_parameter!(kwargs)
        else
          handle_mismatched_profile_parameter!(kwargs, requested_profile_sym, registered_name_sym)
        end
      end
    end

    def registered_profile_name
      ProfileRegistry.all[key] == self ? key.to_sym : nil
    end

    def handle_default_profile_parameter!(kwargs, requested_profile_sym)
      # Default profile: allow profile parameter to override (keep it in kwargs, convert to string for consistency)
      # This enables SlackSender.call(profile: :foo) to work
      kwargs[:profile] = requested_profile_sym.to_s
    end

    def handle_unregistered_profile_parameter!(_kwargs, requested_profile_sym)
      # Unregistered profile: still validate to prevent confusion
      raise ArgumentError, format(ErrorMessages::PROFILE_UNREGISTERED, requested_profile_sym)
    end

    def handle_matching_profile_parameter!(kwargs)
      # Non-default profile with matching profile parameter: strip it out (redundant)
      kwargs.delete(:profile)
    end

    def handle_mismatched_profile_parameter!(_kwargs, requested_profile_sym, registered_name_sym)
      # Non-default profile with non-matching profile parameter: raise error
      raise ArgumentError, format(ErrorMessages::PROFILE_MISMATCH, requested_profile_sym, registered_name_sym, requested_profile_sym)
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
      normalize_for_async_serialization!(kwargs, :blocks)
      normalize_for_async_serialization!(kwargs, :attachments)
    end

    def normalize_for_async_serialization!(kwargs, key)
      if kwargs[key].present?
        kwargs[key] = deep_stringify_keys(kwargs[key])
      else
        kwargs.delete(key)
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
