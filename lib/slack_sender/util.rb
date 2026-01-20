# frozen_string_literal: true

module SlackSender
  module Util
    # Channel-related errors that should not be retried (permanent failures)
    NON_RETRYABLE_CHANNEL_ERRORS = [
      ::Slack::Web::Api::Errors::NotInChannel,
      ::Slack::Web::Api::Errors::ChannelNotFound,
      ::Slack::Web::Api::Errors::IsArchived,
    ].freeze

    def self.non_retryable_channel_error?(exception)
      NON_RETRYABLE_CHANNEL_ERRORS.any? { |klass| exception.is_a?(klass) }
    end

    # Determines retry behavior for Slack API exceptions
    # @param exception [Exception] The exception that occurred
    # @return [Symbol, Integer, nil] :discard to skip retry, Integer (seconds) for custom delay, nil for default retry
    def self.parse_retry_delay_from_exception(exception)
      # Discard known-do-not-retry exceptions
      return :discard if non_retryable_channel_error?(exception)

      # Check for retry headers from Slack (e.g., rate limits)
      if exception.respond_to?(:response_headers) && exception.response_headers.is_a?(Hash)
        retry_after = exception.response_headers["Retry-After"] || exception.response_headers["retry-after"]
        return retry_after.to_i if retry_after.present?
      end

      # Default: let the backend use its default retry behavior
      nil
    end
  end
end
