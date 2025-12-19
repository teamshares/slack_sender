# frozen_string_literal: true

module SlackOutbox
  class DeliveryAxn
    module ExceptionHandlers
      def self.included(base)
        base.on_exception(if: ::Slack::Web::Api::Errors::NotInChannel) do
          send_error_notification <<~MSG
            *Slack Error: Not In Channel*

            Attempted to send message to <##{@resolved_channel}>, but Slackbot is not connected to channel.

            _Instructions:_ https://stackoverflow.com/a/68475477
          MSG
        end

        base.on_exception(if: ::Slack::Web::Api::Errors::ChannelNotFound) do
          send_error_notification <<~MSG
            *Slack Error: Channel Not Found*

            Attempted to send message to <##{@resolved_channel}>, but channel was not found.
            Check if channel was renamed or deleted.
          MSG
        end
      end

      private

      def send_error_notification(message)
        message += "\n\n_Original message:_ \n> #{text.presence || "(blocks/attachments only)"}"

        detail = if error_channel.blank?
                   "NO ERROR CHANNEL CONFIGURED"
                 elsif @resolved_channel == error_channel
                   "WHILE ATTEMPTING TO SEND TO CONFIGURED ERROR CHANNEL (#{error_channel})"
                 end

        return warn("** SLACK MESSAGE SEND FAILED (#{detail}) **. Message: #{message}") if detail.present?

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
end
