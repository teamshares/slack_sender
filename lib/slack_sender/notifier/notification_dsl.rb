# frozen_string_literal: true

module SlackSender
  class Notifier
    # Builder DSL for the `notify do ... end` block.
    # Collects routing, payload, and condition settings into a NotificationDefinition.
    class NotificationDSL
      PAYLOAD_FIELDS = %i[text blocks attachments icon_emoji thread_ts files].freeze

      def initialize
        @channels = []
        @profile = nil
        @condition = nil
        @payload = {}
      end

      # --- Routing ---

      # Set a single channel (literal, symbol method ref, or block)
      def channel(value = nil, &block)
        @channels << (block || value)
      end

      # Set multiple channels
      def channels(*values, &block)
        if block
          @channels << block
        else
          values.flatten.each { |v| @channels << v }
        end
      end

      # Set profile (optional)
      def profile(value = nil, &block)
        @profile = block || value
      end

      # --- Payload ---

      def text(value = nil, &block)
        @payload[:text] = block || value
      end

      def blocks(value = nil, &block)
        @payload[:blocks] = block || value
      end

      def attachments(value = nil, &block)
        @payload[:attachments] = block || value
      end

      def icon_emoji(value = nil, &block)
        @payload[:icon_emoji] = block || value
      end

      def thread_ts(value = nil, &block)
        @payload[:thread_ts] = block || value
      end

      def files(value = nil, &block)
        @payload[:files] = block || value
      end

      # --- Conditions ---

      def only_if(value = nil, &block)
        @condition = block || value
      end

      # Build the final NotificationDefinition
      def build
        NotificationDefinition.new(
          channels: @channels,
          profile: @profile,
          condition: @condition,
          payload: @payload,
        )
      end
    end
  end
end
