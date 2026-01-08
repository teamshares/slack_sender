# frozen_string_literal: true

require_relative "delivery_axn/async_configuration"
require_relative "delivery_axn/exception_handlers"
require_relative "delivery_axn/error_message_parsing"
require_relative "delivery_axn/validation"
require_relative "delivery_axn/channel_resolution"

module SlackSender
  class DeliveryAxn
    include Axn

    # Class method modules (extend)
    extend AsyncConfiguration

    # Instance method modules (include)
    include ExceptionHandlers
    include ErrorMessageParsing
    include Validation
    include ChannelResolution

    expects :profile, type: Profile, preprocess: lambda { |p|
      # If given a string/symbol (profile name), look it up in the registry
      # Otherwise, assume it's already a Profile object
      p.is_a?(Profile) ? p : ProfileRegistry.find(p)
    }
    expects :channel, type: String # NOTE: symbols are preprocessed in Profile#preprocess_call_kwargs
    expects :validate_known_channel, type: :boolean, default: false
    expects :text, type: String, optional: true, preprocess: lambda { |txt|
      ::Slack::Messages::Formatting.markdown(txt) if txt.present?
    }
    expects :icon_emoji, type: String, optional: true, preprocess: lambda { |raw|
      ":#{raw}:".squeeze(":") if raw.present?
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

      done! "Failed successfully: ignoring 'is archived' error per config"
    end

    private

    # TODO: just use memo once we update Axn
    def client = @client ||= ::Slack::Web::Client.new(slack_client_config.merge(token: profile.token))

    # Profile configs
    def slack_client_config = profile.slack_client_config
    def error_channel = profile.error_channel
    def dev_channel = profile.dev_channel

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
      }
      params[:blocks] = blocks if blocks.present?
      params[:attachments] = attachments if attachments.present?
      params[:icon_emoji] = icon_emoji if icon_emoji.present?
      params[:thread_ts] = thread_ts if thread_ts.present?

      response = client.chat_postMessage(**params)
      expose thread_ts: response["ts"]
    end
  end
end
