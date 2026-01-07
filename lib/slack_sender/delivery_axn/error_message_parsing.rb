# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module ErrorMessageParsing
      def self.included(base)
        base.error(if: ::Slack::Web::Api::Errors::SlackError) do |exception:|
          message_from_slack_error(exception)
        end
      end

      private

      def message_from_slack_error(e)
        resp = normalize_response(e.response)
        parts = []

        # Always include the canonical Slack error code
        parts << e.error.to_s

        # Handle common error-specific fields
        parts << "needed=#{resp["needed"]}" if resp["needed"]

        parts << "provided=#{resp["provided"]}" if resp["provided"]

        # Handle response_metadata messages (often the most useful for invalid_arguments)
        meta = e.response_metadata || resp["response_metadata"] || {}
        messages = meta["messages"]
        parts << messages.join("; ") if messages&.any?

        # Fallback: include any remaining useful keys not already handled
        # (optional; keeps logs informative for unknown/new error shapes)
        extra_keys = resp.keys - %w[ok error needed provided response_metadata]
        if extra_keys.any?
          extras = extra_keys.map { |k| "#{k}=#{resp[k].inspect}" }
          parts << extras.join(" ")
        end

        parts.compact.join(" | ")
      end

      def normalize_response(resp)
        return {} if resp.nil?

        # Handle Faraday::Response objects
        if resp.respond_to?(:body)
          body = resp.body
          return body if body.is_a?(Hash)
          return {} unless body.respond_to?(:to_h)

          body.to_h
        elsif resp.is_a?(Hash)
          resp
        else
          # Try to convert to hash if possible
          resp.respond_to?(:to_h) ? resp.to_h : {}
        end
      end
    end
  end
end
