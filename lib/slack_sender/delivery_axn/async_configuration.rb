# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module AsyncConfiguration
      def self.extended(base)
        base._configure_async_backend
      end

      def _configure_async_backend
        backend = SlackSender.config.async_backend

        # No backend configured - will raise error when deliver is called
        return unless backend

        # Backend is already validated by Configuration#async_backend=
        case backend
        when :sidekiq
          async :sidekiq, retry: 5, dead: false
          # Configure Sidekiq-specific retry logic (including skipping retries for InvalidArgumentsError)
          if defined?(Sidekiq::Job) && respond_to?(:sidekiq_retry_in)
            sidekiq_retry_in do |_count, exception|
              # Don't retry invalid arguments
              next :discard if exception.is_a?(SlackSender::InvalidArgumentsError)

              SlackSender::Util.parse_retry_delay_from_exception(exception)
            end
          end
        when :active_job
          async :active_job do
            # Skip retries for invalid arguments - these will never succeed
            discard_on SlackSender::InvalidArgumentsError

            retry_on StandardError, wait: :exponentially_longer, attempts: 5 do |_job, exception|
              retry_behavior = SlackSender::Util.parse_retry_delay_from_exception(exception)
              next if retry_behavior == :discard

              # If retry_behavior is a number (seconds), schedule retry with that delay
              retry_job wait: retry_behavior.seconds if retry_behavior.is_a?(Numeric) && retry_behavior.positive?
              # Otherwise, let ActiveJob use its default retry behavior
            end
          end
        end
      end
    end
  end
end
