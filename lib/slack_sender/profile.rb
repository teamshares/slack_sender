# frozen_string_literal: true

module SlackSender
  class Profile # rubocop:disable Metrics/ClassLength
    # Valid kwargs accepted by Profile#call / Profile#call!
    # These are validated early (before backgrounding) to catch typos like `test:` instead of `text:`
    VALID_CALL_KWARGS = %i[
      channel
      channels
      text
      blocks
      attachments
      icon_emoji
      thread_ts
      file
      files
      slack_options
      profile
    ].freeze

    attr_reader :default_channel, :channels, :user_groups, :slack_client_config, :key, :sandbox

    def initialize(key:, token:, default_channel: nil, channels: {}, user_groups: {}, slack_client_config: {}, sandbox: {})
      @key = key
      @token = token
      @default_channel = default_channel
      @channels = channels.freeze
      @user_groups = user_groups.freeze
      @slack_client_config = slack_client_config.freeze
      @sandbox = normalize_sandbox_config(sandbox).freeze

      validate_sandbox_config!
    end

    def inspect = "<SlackSender::Profile[:#{key}]>"

    # Sandbox accessors for cleaner internal access
    def sandbox_channel = sandbox.dig(:channel, :replace_with)
    def sandbox_channel_message_prefix = sandbox.dig(:channel, :message_prefix)
    def sandbox_user_group = sandbox.dig(:user_group, :replace_with)

    # Resolves the effective sandbox behavior for this profile
    # Resolution order:
    # 1. Explicit sandbox.behavior if set
    # 2. :redirect if sandbox.channel.replace_with is set
    # 3. Global config.sandbox_default_behavior
    def resolved_sandbox_behavior
      return sandbox[:behavior] if sandbox[:behavior]
      return :redirect if sandbox_channel.present?

      SlackSender.config.sandbox_default_behavior
    end

    private

    def normalize_sandbox_config(config)
      return {} if config.nil? || config.empty?

      result = {
        channel: normalize_sandbox_channel(config[:channel]),
        user_group: normalize_sandbox_user_group(config[:user_group]),
      }.compact

      # Extract and validate behavior if present. Shares Configuration::SUPPORTED_SANDBOX_BEHAVIORS
      # (single source of truth) and mirrors its `one_of:` DSL wording, so a mistyped
      # `sandbox: { behavior: ... }` and a mistyped `config.sandbox_default_behavior =` read the
      # same way.
      if config[:behavior]
        behavior = config[:behavior].to_sym
        supported = Configuration::SUPPORTED_SANDBOX_BEHAVIORS
        unless supported.include?(behavior)
          raise ArgumentError,
                "sandbox.behavior must be one of #{supported.map(&:inspect).join(", ")}; got #{behavior.inspect}"
        end
        result[:behavior] = behavior
      end

      result
    end

    def normalize_sandbox_channel(channel_config)
      return nil if channel_config.nil?

      channel_config.slice(:replace_with, :message_prefix).compact.presence
    end

    def normalize_sandbox_user_group(user_group_config)
      return nil if user_group_config.nil?

      user_group_config.slice(:replace_with).compact.presence
    end

    def validate_sandbox_config!
      # If explicit behavior is :redirect, channel.replace_with is required
      return unless sandbox[:behavior] == :redirect && sandbox_channel.blank?

      raise ArgumentError, ErrorMessages::SANDBOX_REDIRECT_REQUIRES_CHANNEL
    end

    public

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

      unless ProfileRegistry.all[key] == self
        raise Error,
              "Profile must be registered before using async delivery. Register it with SlackSender.register(name, config)"
      end

      if kwargs[:channels]
        dispatch_to_channels(kwargs)
      else
        preprocess_files_for_async!(kwargs)
        DeliveryAxn.call_async(profile: key.to_s, **kwargs)
      end
      true
    end

    def call!(**)
      enabled, kwargs = enabled_and_preprocessed_kwargs(**)
      return false unless enabled

      raise ArgumentError, ErrorMessages::MULTI_CHANNEL_SYNC_NOT_SUPPORTED if kwargs[:channels]

      DeliveryAxn.call!(profile: self, **kwargs).thread_ts
    end

    def group_link(key)
      group_id = if key.is_a?(Symbol)
                   user_groups[key] || raise("Unknown user group: #{key}")
                 else
                   key
                 end

      group_id = sandbox_user_group if sandbox_user_group.present? && SlackSender.config.sandbox_mode?

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

    def enabled_and_preprocessed_kwargs(**kwargs)
      return [false, nil] unless SlackSender.config.enabled
      return [false, nil] if Util.blank_text_only?(kwargs)

      [true, preprocess_call_kwargs(kwargs)]
    end

    # Handles multi-channel async delivery by enqueuing a separate job for each channel.
    # Files are preprocessed once (uploaded if needed) and the same file_ids are used for all channels.
    def dispatch_to_channels(kwargs)
      channels = kwargs.delete(:channels)
      preprocess_files_for_async!(kwargs) # Upload once, get file_ids

      channels.each do |ch|
        channel_kwargs = kwargs.dup
        channel_kwargs[:channel] = ch
        preprocess_channel!(channel_kwargs) # Convert symbol -> string + validate flag
        DeliveryAxn.call_async(profile: key.to_s, **channel_kwargs)
      end
    end

    # Handles file preprocessing for async delivery.
    # Files are uploaded to Slack synchronously before enqueueing the job;
    # the job then shares the uploaded files via file_ids.
    def preprocess_files_for_async!(kwargs)
      return unless kwargs[:files].present?

      wrapped = MultiFileWrapper.new(kwargs.delete(:files))
      wrapped.validate_for_async!

      kwargs[:file_ids] = FileUploader.new(client, wrapped.files).upload_to_slack
    end

    def preprocess_call_kwargs(raw)
      raw.dup.tap do |kwargs|
        validate_known_kwargs!(kwargs)
        normalize_file_to_files!(kwargs)
        normalize_and_apply_channels!(kwargs)
        validate_and_handle_profile_parameter!(kwargs)
        preprocess_blocks_and_attachments!(kwargs)
      end
    end

    def normalize_file_to_files!(kwargs)
      return unless kwargs.key?(:file)

      raise ArgumentError, ErrorMessages::FILE_AND_FILES_CONFLICT if kwargs.key?(:files)

      kwargs[:files] = [kwargs.delete(:file)]
    end

    def normalize_and_apply_channels!(kwargs)
      normalizer = ChannelNormalizer.new(
        channel: kwargs.delete(:channel),
        channels: kwargs.delete(:channels),
      )
      normalizer.apply_default!(default_channel)
      normalizer.preprocess_channel!
      kwargs.merge!(normalizer.to_kwargs)
    end

    def validate_known_kwargs!(kwargs)
      unknown_keys = kwargs.keys - VALID_CALL_KWARGS
      return if unknown_keys.empty?

      raise ArgumentError, format(
        ErrorMessages::UNKNOWN_KWARGS,
        unknown_keys.map(&:inspect).join(", "),
        VALID_CALL_KWARGS.join(", "),
      )
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
      # Convert symbol keys to strings in blocks, attachments, and slack_options for JSON
      # serialization. This ensures they're serializable for async jobs (Sidekiq/ActiveJob) —
      # Sidekiq's strict argument checking rejects symbol keys nested in job args at enqueue time.
      normalize_for_async_serialization!(kwargs, :blocks)
      normalize_for_async_serialization!(kwargs, :attachments)
      normalize_for_async_serialization!(kwargs, :slack_options)
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
