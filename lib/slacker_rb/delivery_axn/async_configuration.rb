# frozen_string_literal: true

module Slacker
  class DeliveryAxn
    module AsyncConfiguration
      def self.extended(base)
        base._configure_async_backend
      end

      def _configure_async_backend
        backend = Slacker.config.async_backend

        # No backend configured - will raise error when deliver is called
        return unless backend

        unless Slacker::Configuration::SUPPORTED_ASYNC_BACKENDS.include?(backend)
          raise ArgumentError,
                "Unsupported async backend: #{backend.inspect}. " \
                "Supported backends: #{Slacker::Configuration::SUPPORTED_ASYNC_BACKENDS.inspect}. " \
                "Please update Slacker to support this backend."
        end

        case backend
        when :sidekiq
          async :sidekiq, retry: 5, dead: false
          # Configure Sidekiq-specific retry logic
          if defined?(Sidekiq::Job) && respond_to?(:sidekiq_retry_in)
            sidekiq_retry_in do |_count, exception|
              Slacker::Util.parse_retry_delay_from_slack_exception(exception)
            end
          end
        when :active_job
          async :active_job do
            retry_on StandardError, wait: :exponentially_longer, attempts: 5 do |_job, exception|
              retry_behavior = Slacker::Util.parse_retry_delay_from_slack_exception(exception)
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
