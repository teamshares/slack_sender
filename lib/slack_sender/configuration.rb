# frozen_string_literal: true

module SlackSender
  class Configuration
    SUPPORTED_ASYNC_BACKENDS = %i[sidekiq active_job].freeze
    SUPPORTED_SANDBOX_BEHAVIORS = %i[noop redirect passthrough].freeze

    attr_writer :sandbox_mode
    attr_accessor :enabled, :silence_archived_channel_exceptions

    def initialize
      # Default values
      @enabled = true
      @sandbox_default_behavior = :noop
    end

    def sandbox_mode?
      return @sandbox_mode unless @sandbox_mode.nil?

      if defined?(Rails) && Rails.respond_to?(:env)
        !Rails.env.production?
      else
        true
      end
    end

    attr_reader :sandbox_default_behavior

    def sandbox_default_behavior=(value)
      unless SUPPORTED_SANDBOX_BEHAVIORS.include?(value)
        raise ArgumentError,
              "Unsupported sandbox behavior: #{value.inspect}. " \
              "Supported behaviors: #{SUPPORTED_SANDBOX_BEHAVIORS.inspect}"
      end

      @sandbox_default_behavior = value
    end

    def async_backend
      @async_backend ||= detect_default_async_backend
    end

    def async_backend=(value)
      if value && !SUPPORTED_ASYNC_BACKENDS.include?(value)
        raise ArgumentError,
              "Unsupported async backend: #{value.inspect}. " \
              "Supported backends: #{SUPPORTED_ASYNC_BACKENDS.inspect}. " \
              "Please update SlackSender to support this backend."
      end

      @async_backend = value
    end

    def async_backend_available?
      backend = async_backend
      return false unless backend

      case backend
      when :sidekiq
        defined?(Sidekiq::Job)
      when :active_job
        defined?(ActiveJob::Base)
      else
        false
      end
    end

    private

    def detect_default_async_backend
      return :sidekiq if defined?(Sidekiq::Job)
      return :active_job if defined?(ActiveJob::Base)

      nil
    end
  end

  class << self
    def config = @config ||= Configuration.new

    def configure
      self.config ||= Configuration.new
      yield(config) if block_given?
    end
  end
end
