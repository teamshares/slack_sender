# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module ExceptionHandlers
      def self.included(base)
        # Log warnings for all Slack API errors
        # Channel-related errors (NotInChannel, ChannelNotFound, IsArchived) use a different prefix
        # to distinguish "message send failed" from other API errors (auth failures, etc.)
        base.on_exception(:log_warning_from_exception, if: ::Slack::Web::Api::Errors::SlackError)
      end

      private

      def log_warning_from_exception(exception:)
        prefix = SlackSender::Util.non_retryable_channel_error?(exception) ? "SLACK MESSAGE SEND FAILED: " : "SLACK API ERROR: "
        msg = format_warning_message(exception, prefix, profile, channel_display, text)
        self.class.warn(msg)
      end

      def format_warning_message(exception, prefix, profile, channel_display, text)
        [
          "** #{prefix}#{exception.class.name.demodulize.titleize} **.\n",
          (profile.key == :default ? nil : "Profile: #{profile.key}\n"),
          "Channel: #{channel_display}\n",
          "Message: #{text.presence || "(blocks/attachments only)"}",
        ].compact_blank.join
      end
    end
  end
end
