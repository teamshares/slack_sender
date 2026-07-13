# frozen_string_literal: true

module SlackSender
  # Axn strategy that provides `slack(...)` and `slack!(...)` methods for sending Slack messages.
  #
  # Usage:
  #   class MyAction
  #     include Axn
  #     use :slack, channel: :general
  #
  #     on_success { slack "It worked!" }
  #
  #     def call
  #       slack "Processing..."
  #       # ...
  #     end
  #   end
  #
  # Configuration options:
  #   channel: - Default channel for all slack() calls (can be overridden per-call)
  #   profile: - SlackSender profile to use (default: :default)
  #
  # All options can be overridden per-call. Call-time values take precedence over defaults.
  #
  # Methods:
  #   slack(...)  - Async delivery via background job (recommended, enables auto-retry)
  #   slack!(...) - Sync delivery in foreground (immediate execution, no auto-retry)
  #
  module Strategy
    def self.configure(**defaults)
      Module.new do
        extend ActiveSupport::Concern

        included do
          define_method(:__slack_defaults) { defaults }
          private :__slack_defaults
        end

        # Send a Slack message asynchronously via background job.
        # Enables automatic retries for failed sends.
        #
        # @param text [String, nil] Optional positional argument for message text (sugar for text: kwarg)
        # @param kwargs [Hash] SlackSender options (channel:, profile:, blocks:, attachments:, icon_emoji:, etc.)
        # @return [true, false] true if message was enqueued, false if sending is disabled
        # @raise [ArgumentError] If no channel specified and no default configured
        # @raise [SlackSender::Error] If no async backend is configured
        #
        # Examples:
        #   slack "Hello"                           # positional text, uses default channel
        #   slack "Hello", channel: :other          # positional text, override channel
        #   slack text: "Hello", channel: :other    # explicit kwargs
        #   slack channel: :foo, text: "Hi", blocks: [...]  # full kwargs
        #   slack "Hi", profile: :other_profile     # override profile for this call
        #
        def slack(text = nil, **kwargs)
          __slack_deliver(text, :call, **kwargs)
        end

        # Send a Slack message synchronously in the foreground.
        # Use when you need immediate execution or the thread_ts return value.
        #
        # @param text [String, nil] Optional positional argument for message text (sugar for text: kwarg)
        # @param kwargs [Hash] SlackSender options (channel:, profile:, blocks:, attachments:, icon_emoji:, etc.)
        # @return [String, nil] Thread timestamp from Slack response, or false if sending is disabled
        # @raise [ArgumentError] If no channel specified and no default configured
        #
        # Examples:
        #   thread_ts = slack! "Hello"              # get thread_ts for replies
        #   slack! "Urgent!", channel: :alerts      # immediate delivery
        #
        def slack!(text = nil, **kwargs)
          __slack_deliver(text, :call!, **kwargs)
        end

        private

        def __slack_deliver(text, method, **kwargs)
          kwargs[:text] = text if text

          # Merge defaults with call-time kwargs (call-time wins)
          merged = __slack_defaults.merge(kwargs)

          channel = merged.delete(:channel)
          channels = merged.delete(:channels)
          profile = merged.delete(:profile) || :default

          raise ArgumentError, "No channel(s) specified and no default channel configured" unless channel || channels

          # Resolve this action's per-class sandbox override (configure(:slack_sender)) at the origin,
          # where the action class is known, and thread it down. :inherit when unset leaves global
          # config in charge — unchanged for every action that doesn't opt in.
          found, override = SlackSender::Configuration.class_override(self.class, :sandbox_mode)
          sandbox_mode = found ? override : :inherit
          target = SlackSender.profile(profile)

          if channels
            target.public_send(method, channels:, sandbox_mode:, **merged)
          else
            target.public_send(method, channel:, sandbox_mode:, **merged)
          end
        end
      end
    end
  end
end
