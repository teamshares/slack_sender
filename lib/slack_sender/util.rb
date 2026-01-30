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

    # Checks if kwargs represent an explicit blank text-only call (no other content keys).
    # Used to treat such calls as no-ops rather than errors.
    # @param kwargs [Hash] The keyword arguments to check
    # @return [Boolean] true if text is the only content key and is blank
    def self.blank_text_only?(kwargs)
      # Check for presence (not just key existence) since provided_data may include
      # empty arrays from defaults
      kwargs.key?(:text) &&
        kwargs[:text].is_a?(String) &&
        kwargs[:text].blank? &&
        kwargs[:blocks].blank? &&
        kwargs[:attachments].blank? &&
        kwargs[:file].blank? &&
        kwargs[:files].blank?
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

    # Extracts the needed scope from a MissingScope exception.
    # Tries multiple locations since slack-ruby-client's structure varies:
    # - response_metadata["needed"] (documented but not always present)
    # - response.body.needed (Slack::Messages::Message object)
    # - HTTP header x-accepted-oauth-scopes
    # @param exception [Slack::Web::Api::Errors::MissingScope] The exception
    # @return [String, nil] The needed scope, or nil if not found
    def self.extract_needed_scope(exception)
      # Try response_metadata first (documented location)
      exception.response_metadata&.dig("needed") ||
        # Try response.body which is a Slack::Messages::Message
        exception.response&.body&.try(:needed) ||
        exception.response&.body&.try(:[], "needed") ||
        # Try HTTP headers as fallback
        exception.response&.env&.dig(:response_headers, "x-accepted-oauth-scopes")
    end

    # Builds a descriptive error message for MissingScope exceptions.
    # @param exception [Slack::Web::Api::Errors::MissingScope] The exception
    # @return [String] A user-friendly error message
    def self.missing_scope_error_message(exception)
      needed = extract_needed_scope(exception)
      if needed.present?
        format(ErrorMessages::MISSING_SCOPE, needed)
      else
        ErrorMessages::MISSING_SCOPE_UNKNOWN
      end
    end
  end
end
