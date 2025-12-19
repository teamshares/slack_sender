# frozen_string_literal: true

module SlackOutbox
  class DeliveryAxn
    include Axn

    expects :profile, type: Profile
    expects :channel # Symbol or String - resolved in before block
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
      files_array = Array(raw).presence
      files_array&.each_with_index&.map { |f, i| SlackOutbox::FileWrapper.wrap(f, i) }
    }

    exposes :thread_ts, type: String

    before do
      # Resolve channel symbol to ID using profile's channels
      @resolved_channel = resolve_channel(channel)
      fail! "channel must resolve to a String" unless @resolved_channel.is_a?(String)

      fail! "Must provide at least one of: text, blocks, attachments, or files" if content_blank?
      fail! "Provided blocks were invalid" if blocks.present? && !blocks_valid?

      if files.present?
        fail! "Cannot provide files with blocks" if blocks.present?
        fail! "Cannot provide files with attachments" if attachments.present?
        fail! "Cannot provide files with icon_emoji" if icon_emoji.present?
      end
    end

    async :sidekiq, retry: 5, dead: false

    def call
      if files.present?
        upload_files
      else
        post_message
      end
    rescue ::Slack::Web::Api::Errors::NotInChannel
      handle_not_in_channel
      raise # Re-raise; sidekiq_retry_in returns :discard, so no retries
    rescue ::Slack::Web::Api::Errors::ChannelNotFound
      handle_channel_not_found
      raise # Re-raise; sidekiq_retry_in returns :discard, so no retries
      # All other errors pass through for Sidekiq retry (up to 5 times)
    end

    def self.format_group_mention(profile, key, non_production = nil)
      group_id = if key.is_a?(Symbol)
                   profile.user_groups[key] || raise("Unknown user group: #{key}")
                 else
                   key
                 end

      group_id = non_production.presence || profile.user_groups[:slack_development] unless SlackOutbox.config.in_production?

      ::Slack::Messages::Formatting.group_link(group_id)
    end

    private

    def slack_client_config = {}
    def dev_channel = profile.dev_channel
    def error_channel = profile.error_channel

    # Implementation helpers
    def resolve_channel(raw)
      return raw unless raw.is_a?(Symbol)

      profile.channels[raw] || fail!("Unknown channel: #{raw}")
    end

    def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank?

    # TODO: just use memo once we update Axn
    def client = @client ||= ::Slack::Web::Client.new(slack_client_config.merge(token: profile.token))

    def upload_files
      file_uploads = files.map(&:to_h)
      response = client.files_upload_v2(
        files: file_uploads,
        channel: channel_for_environment,
        initial_comment: text_for_environment,
      )

      # files_upload_v2 doesn't return thread_ts directly, so we fetch it via files.info
      file_id = response.dig("files", 0, "id")
      return unless file_id

      file_info = client.files_info(file: file_id)
      ts = file_info.dig("file", "shares", "public", channel_for_environment, 0, "ts") ||
           file_info.dig("file", "shares", "private", channel_for_environment, 0, "ts")
      expose thread_ts: ts if ts
    end

    def post_message
      response = client.chat_postMessage(
        channel: channel_for_environment,
        text: text_for_environment,
        blocks:,
        attachments:,
        icon_emoji:,
        thread_ts:,
      )
      expose thread_ts: response["ts"]
    end

    def blocks_valid?
      return false if blocks.blank?

      return true if blocks.all? do |single_block|
        # TODO: Add better validations against slack block kit API
        single_block.is_a?(Hash) && (single_block.key?(:type) || single_block.key?("type"))
      end

      false
    end

    def channel_for_environment
      return @resolved_channel if SlackOutbox.config.in_production?
      return dev_channel if dev_channel.present?

      @resolved_channel
    end

    def text_for_environment
      return text if SlackOutbox.config.in_production?
      return nil if text.blank?

      test_message_wrapper
    end

    def test_message_wrapper
      formatted_message = text.lines.map { |line| "> #{line}" }.join

      <<~TEXT.strip
        _:test_tube: This is a test. Would have been sent to <##{@resolved_channel}> in production. :test_tube:_

        #{formatted_message}
      TEXT
    end

    # Error handlers - send notification then re-raise
    # sidekiq_retry_in will discard these (no retries)
    def handle_not_in_channel
      error_message = <<~MSG
        *Slack Error: Not In Channel*

        Attempted to send message to <##{@resolved_channel}>, but Slackbot is not connected to channel.

        _Instructions:_ https://stackoverflow.com/a/68475477

        _Original message:_
        > #{text || "(blocks/attachments only)"}
      MSG

      send_error_notification(error_message)
    end

    def handle_channel_not_found
      error_message = <<~MSG
        *Slack Error: Channel Not Found*

        Attempted to send message to <##{@resolved_channel}>, but channel was not found.
        Check if channel was renamed or deleted.

        _Original message:_
        > #{text || "(blocks/attachments only)"}
      MSG

      send_error_notification(error_message)
    end

    def send_error_notification(message)
      if error_channel.blank?
        warn "** SLACK MESSAGE SEND FAILED (AND NO ERROR CHANNEL CONFIGURED) **. Message: #{message}"
        return
      end

      # Avoid infinite loop if error_channel itself has issues
      return if @resolved_channel == error_channel

      # Send directly, don't use call_async to avoid Sidekiq queue
      self.class.call!(profile:, channel: error_channel, text: message)
    rescue StandardError => e
      # Last resort: notify error notifier if configured, otherwise Honeybadger if available
      if SlackOutbox.config.error_notifier
        SlackOutbox.config.error_notifier.call(e, context: { original_error_message: message })
      elsif defined?(Honeybadger)
        Honeybadger.notify(e, context: { original_error_message: message })
      end
    end
  end
end

