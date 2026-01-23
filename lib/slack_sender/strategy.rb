# frozen_string_literal: true

module SlackSender
  # Axn strategy that provides a `slack(...)` method for sending Slack messages.
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
  module Strategy
    def self.configure(**defaults)
      Module.new do
        extend ActiveSupport::Concern

        included do
          define_method(:__slack_defaults) { defaults }
          private :__slack_defaults
        end

        # Send a Slack message.
        #
        # @param text [String, nil] Optional positional argument for message text (sugar for text: kwarg)
        # @param kwargs [Hash] SlackSender options (channel:, profile:, blocks:, attachments:, icon_emoji:, etc.)
        # @return [String, nil] Thread timestamp from Slack response
        # @raise [ArgumentError] If no channel specified and no default configured
        #
        # Examples:
        #   slack "Hello"                           # positional text, uses default channel
        #   slack "Hello", channel: :other          # positional text, override channel
        #   slack text: "Hello", channel: :other    # explicit kwargs
        #   slack channel: :foo, text: "Hi", blocks: [...]  # full kwargs
        #   slack "Hi", profile: :other_profile     # override profile for this call
        #
        def slack(text = nil, **kwargs)
          kwargs[:text] = text if text

          # Merge defaults with call-time kwargs (call-time wins)
          merged = __slack_defaults.merge(kwargs)

          channel = merged.delete(:channel)
          profile = merged.delete(:profile) || :default

          raise ArgumentError, "No channel specified and no default channel configured" unless channel

          SlackSender.profile(profile).call!(channel:, **merged)
        end
      end
    end
  end
end
