# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module ChannelResolution
      protected

      def channel_to_use
        redirect_to_dev_channel? ? dev_channel : channel
      end

      def text_to_use
        return text unless redirect_to_dev_channel?

        formatted_message = text&.lines&.map { |line| "> #{line}" }&.join

        [
          dev_channel_redirect_prefix,
          formatted_message,
        ].compact_blank.join("\n\n")
      end

      private

      def redirect_to_dev_channel? = dev_channel.present? && !SlackSender.config.in_production?

      def channel_display
        is_channel_id?(channel) ? Slack::Messages::Formatting.channel_link(channel) : "`#{channel}`"
      end

      # TODO: this is directionally correct, but more-correct would involve conversations.list
      def is_channel_id?(given) # rubocop:disable Naming/PredicatePrefix
        given[0] != "#" && given.match?(/\A[CGD][A-Z0-9]+\z/)
      end

      def default_dev_channel_redirect_prefix = ":construction: _This message would have been sent to %s in production_"

      def dev_channel_redirect_prefix
        format(profile.dev_channel_redirect_prefix.presence || default_dev_channel_redirect_prefix, channel_display)
      end
    end
  end
end
