# frozen_string_literal: true

module SlackSender
  # Encapsulates channel normalization logic for call kwargs.
  # Handles:
  # - Conflict validation (channel: vs channels:)
  # - Empty channels validation
  # - Single-element array normalization (channels: [:foo] -> channel: :foo)
  # - Symbol to string preprocessing with validation flag
  # - Default channel application
  class ChannelNormalizer
    attr_reader :channel, :channels, :validate_known_channel

    def initialize(channel: nil, channels: nil)
      validate_conflict!(channel, channels)
      @channel, @channels = normalize(channel, channels)
      @validate_known_channel = false
    end

    def single? = @channels.nil?
    def multi? = !single?

    # Converts symbol channel to string and flags for validation
    def preprocess_channel!
      return unless @channel.is_a?(Symbol)

      @channel = @channel.to_s
      @validate_known_channel = true
    end

    # Apply default if no channel specified
    def apply_default!(default_channel)
      return if @channel.present? || @channels.present?

      @channel = default_channel if default_channel.present?
    end

    # Returns kwargs to merge back
    def to_kwargs
      if @channels
        { channels: @channels }
      elsif @channel
        result = { channel: @channel }
        result[:validate_known_channel] = true if @validate_known_channel
        result
      else
        {}
      end
    end

    private

    def validate_conflict!(channel, channels)
      return unless channel && channels

      raise ArgumentError, ErrorMessages::CHANNEL_AND_CHANNELS_CONFLICT
    end

    def normalize(channel, channels)
      return [channel, nil] unless channels

      channels_array = Array(channels)
      raise ArgumentError, ErrorMessages::EMPTY_CHANNELS if channels_array.empty?

      if channels_array.size == 1
        [channels_array.first, nil]
      else
        [nil, channels_array]
      end
    end
  end
end
