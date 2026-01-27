# frozen_string_literal: true

module SlackSender
  class Notifier
    # Holds a notification specification (routing + condition + payload).
    # Evaluated at runtime in the context of a Notifier instance.
    class NotificationDefinition
      attr_reader :channels, :profile, :condition, :payload

      def initialize(channels:, profile:, condition:, payload:)
        @channels = channels
        @profile = profile
        @condition = condition
        @payload = payload
      end

      # Execute this notification definition in the given notifier instance context.
      # Resolves all values (literals, symbols, blocks) and sends via slack().
      def execute(notifier)
        # Check condition first
        return if condition && !resolve(condition, notifier)

        # Resolve channels
        resolved_channels = channels.flat_map { |ch| resolve(ch, notifier) }

        # Validate: at least one channel
        raise ArgumentError, "Missing `channel` in notify block. Add `channel :foo` or `channels ...`." if resolved_channels.compact.empty?

        # Resolve payload
        resolved_payload = payload.transform_values { |v| resolve(v, notifier) }.compact

        # Validate: at least one payload field
        raise ArgumentError, "Missing payload in notify block. Add `text`, `blocks`, `attachments`, or `files`." if resolved_payload.empty?

        # Resolve profile if specified
        resolved_profile = profile ? resolve(profile, notifier) : nil

        # Send to each channel
        resolved_channels.compact.each do |ch|
          kwargs = resolved_payload.dup
          kwargs[:profile] = resolved_profile if resolved_profile
          notifier.send(:slack, channel: ch, **kwargs)
        end
      end

      private

      # Resolve a value: block → instance_exec, symbol → method call (if exists) or literal, else literal
      def resolve(value, notifier)
        case value
        when Proc
          notifier.instance_exec(&value)
        when Symbol
          notifier.respond_to?(value, true) ? notifier.send(value) : value
        else
          value
        end
      end
    end
  end
end
