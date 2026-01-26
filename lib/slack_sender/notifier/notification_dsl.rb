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

      def channel(value = nil, &block)
        @channels << (block || value)
      end

      def channels(*values, &block)
        if block
          @channels << block
        else
          values.flatten.each { |v| @channels << v }
        end
      end

      # --- Payload + Options (generated) ---

      PAYLOAD_FIELDS.each do |field|
        define_method(field) do |value = nil, &block|
          @payload[field] = block || value
        end
      end

      def profile(value = nil, &block)
        @profile = block || value
      end

      def only_if(value = nil, &block)
        @condition = block || value
      end

      # --- Build ---

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
