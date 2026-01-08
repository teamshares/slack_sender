# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module ExceptionHandlers
      def self.included(base)
        base.on_exception(if: ::Slack::Web::Api::Errors::NotInChannel) do |exception:|
          report_exception_to_slack_error_channel(
            exception:,
            description: "Slackbot is not connected to channel",
            cta: "_Instructions:_ https://stackoverflow.com/a/68475477",
          )
        end

        base.on_exception(if: ::Slack::Web::Api::Errors::ChannelNotFound) do |exception:|
          report_exception_to_slack_error_channel(
            exception:,
            description: "channel was not found",
            cta: "Check if channel was renamed or deleted.",
          )
        end

        # Only reaches here if ignore_archived_errors is false/nil
        # (if true, it's handled in call method with done!)
        base.on_exception(if: ::Slack::Web::Api::Errors::IsArchived) do |exception:|
          report_exception_to_slack_error_channel(
            exception:,
            description: "channel is archived",
            cta: "Unarchive the channel or use a different channel.",
          )
        end

        # Catch-all for other SlackError exceptions (auth failures, etc.)
        # These can't send to error_channel, so just log warnings
        base.on_exception(:log_warning_from_exception, if: lambda { |e|
          e.is_a?(::Slack::Web::Api::Errors::SlackError) &&
          !e.is_a?(::Slack::Web::Api::Errors::NotInChannel) &&
          !e.is_a?(::Slack::Web::Api::Errors::ChannelNotFound) &&
          !e.is_a?(::Slack::Web::Api::Errors::IsArchived)
        })
      end

      private

      def log_warning_from_exception(exception:, prefix: "SLACK API ERROR: ")
        msg = [
          "** #{prefix}#{exception.class.name.demodulize.titleize} **.\n",
          (profile.key == :default ? nil : "Profile: #{profile.key}\n"),
          "Channel: #{channel_display}\n",
          "Message: #{text.presence || "(blocks/attachments only)"}",
        ].compact_blank.join

        self.class.warn(msg)
      end

      # NOTE: only the three special cases will report via Slack... nice user facing feature if channel wrong but
      # we may just remove this layer in the future to simplify + make explainable + avoid bulk reports
      def report_exception_to_slack_error_channel(exception:, description: nil, cta: nil)
        return log_warning_from_exception(exception:, prefix: "SLACK MESSAGE SEND FAILED: ") if error_channel.blank? || channel == error_channel

        message = [
          "*Slack Error: #{exception.class.name.demodulize.titleize}*\n",
          "#{["Attempted to send message to #{channel_display}", description].compact_blank.join(", but ")}\n",
          cta,
          "\n_Original message:_ \n> #{text.presence || "(blocks/attachments only)"}",
        ].compact_blank.join("\n")

        # Send directly, don't use call_async to avoid Sidekiq queue
        # Use the client directly to bypass channel resolution and ensure we send to error_channel
        begin
          client.chat_postMessage(channel: error_channel, text: message)
        rescue StandardError => e
          log_warning_from_exception(exception: e, prefix: "SLACK MESSAGE SEND FAILED (WHILE REPORTING ERROR: #{exception.class.name}")
        end
      end
    end
  end
end
