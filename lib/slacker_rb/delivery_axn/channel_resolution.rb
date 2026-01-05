# frozen_string_literal: true

module Slacker
  class DeliveryAxn
    module ChannelResolution
      protected

      # TODO: just use memo once we update Axn
      def channel_to_use = redirect_to_dev_channel? ? dev_channel : @resolved_channel

      # TODO: just use memo once we update Axn
      def text_to_use
        return text unless redirect_to_dev_channel?

        formatted_message = text&.lines&.map { |line| "> #{line}" }&.join

        [
          dev_channel_redirect_prefix,
          formatted_message,
        ].compact_blank.join("\n\n")
      end

      private

      def redirect_to_dev_channel? = dev_channel.present? && !Slacker.config.in_production?

      def channel_display = is_channel_id?(@resolved_channel) ? Slack::Messages::Formatting.channel_link(@resolved_channel) : "`<##{@resolved_channel}`"

      # TODO: this is directionally correct, but more-correct would involve conversations.list
      def is_channel_id?(given) = given[0] != "#" && given.match?(/\A[CGD][A-Z0-9]+\z/) # rubocop:disable Naming/PredicatePrefix

      def default_dev_channel_redirect_prefix = ":construction: _This message would have been sent to `%s` in production_"

      def dev_channel_redirect_prefix
        format(profile.dev_channel_redirect_prefix.presence || default_dev_channel_redirect_prefix, channel_display)
      end
    end
  end
end
