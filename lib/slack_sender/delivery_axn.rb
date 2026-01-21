# frozen_string_literal: true

require_relative "delivery_axn/async_configuration"
require_relative "delivery_axn/exception_handlers"
require_relative "delivery_axn/error_message_parsing"
require_relative "delivery_axn/validation"

module SlackSender
  class DeliveryAxn
    include Axn

    # Class method modules (extend)
    extend AsyncConfiguration

    # Instance method modules (include)
    include ExceptionHandlers
    include ErrorMessageParsing
    include Validation

    expects :profile, type: Profile, preprocess: lambda { |p|
      # If given a string/symbol (profile name), look it up in the registry
      # Otherwise, assume it's already a Profile object
      p.is_a?(Profile) ? p : ProfileRegistry.find(p)
    }
    expects :validate_known_channel, type: :boolean, default: false
    expects :channel, type: String, preprocess: lambda { |ch|
      # NOTE: symbols are preprocessed to strings in Profile#preprocess_call_kwargs
      validate_known_channel ? (profile.channels[ch.to_sym] || fail!(format(ErrorMessages::UNKNOWN_CHANNEL, ch))) : ch
    }
    expects :text, type: String, optional: true, preprocess: lambda { |txt|
      ::Slack::Messages::Formatting.markdown(txt) if txt.present?
    }
    expects :icon_emoji, type: String, optional: true, preprocess: lambda { |raw|
      normalize_icon_emoji(raw)
    }
    expects :blocks, type: Array, optional: true
    expects :attachments, type: Array, optional: true
    expects :thread_ts, type: String, optional: true
    expects :files, type: Array, optional: true, preprocess: lambda { |raw|
      MultiFileWrapper.new(raw).files
    }

    exposes :thread_ts, type: String, optional: true

    def call
      files.present? ? upload_files : post_message
    rescue Slack::Web::Api::Errors::IsArchived => e
      raise(e) unless SlackSender.config.silence_archived_channel_exceptions

      done! ErrorMessages::ARCHIVED_CHANNEL_SILENCED
    end

    private

    def normalize_icon_emoji(raw)
      ":#{raw}:".squeeze(":") if raw.present?
    end

    memo def client = ::Slack::Web::Client.new(slack_client_config.merge(token: profile.token))

    # Profile configs
    def slack_client_config = profile.slack_client_config
    def error_channel = profile.error_channel
    def dev_channel = profile.dev_channel

    # Dev channel redirection
    memo def channel_to_use = redirect_to_dev_channel? ? dev_channel : channel
    memo def text_to_use
      return text unless redirect_to_dev_channel?

      formatted_message = text&.lines&.map { |line| "> #{line}" }&.join

      [
        dev_channel_redirect_prefix,
        formatted_message,
      ].compact_blank.join("\n\n")
    end

    # Dev channel redirection - helpers
    def redirect_to_dev_channel? = dev_channel.present? && !SlackSender.config.in_production?
    def channel_display = channel_id?(channel) ? Slack::Messages::Formatting.channel_link(channel) : "`#{channel}`"

    def dev_channel_redirect_prefix
      format(profile.dev_channel_redirect_prefix.presence || ErrorMessages::DEFAULT_DEV_CHANNEL_REDIRECT_PREFIX,
             channel_display)
    end

    # TODO: this is directionally correct, but more-correct would involve conversations.list
    def channel_id?(given)
      given[0] != "#" && given.match?(/\A[CGD][A-Z0-9]+\z/)
    end

    # Core sending methods
    def upload_files
      file_uploads = files.map(&:to_h)
      response = client.files_upload_v2(
        files: file_uploads,
        channel: channel_to_use,
        initial_comment: text_to_use,
      )

      # files_upload_v2 doesn't return thread_ts directly, so we fetch it via files.info
      file_id = response.dig("files", 0, "id")
      return unless file_id

      file_info = client.files_info(file: file_id)
      ts = file_info.dig("file", "shares", "public", channel_to_use, 0, "ts") ||
           file_info.dig("file", "shares", "private", channel_to_use, 0, "ts")
      expose thread_ts: ts if ts
    end

    def post_message
      params = {
        channel: channel_to_use,
        text: text_to_use,
        blocks:,
        attachments:,
        icon_emoji:,
        thread_ts:,
      }.compact_blank

      response = client.chat_postMessage(**params)
      expose thread_ts: response["ts"]
    end
  end
end
