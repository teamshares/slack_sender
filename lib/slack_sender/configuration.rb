# frozen_string_literal: true

module SlackSender
  class Configuration
    SUPPORTED_ASYNC_BACKENDS = %i[sidekiq active_job].freeze
    SUPPORTED_SANDBOX_BEHAVIORS = %i[noop redirect passthrough].freeze

    # Slack's hard limit per file (1 GB)
    SLACK_MAX_FILE_SIZE = 1_073_741_824

    # Default file size thresholds
    DEFAULT_MAX_INLINE_FILE_SIZE = 524_288 # 512 KB - conservative for Redis/Sidekiq payloads
    DEFAULT_MAX_ASYNC_FILE_UPLOAD_SIZE = 26_214_400 # 25 MB

    attr_writer :sandbox_mode
    attr_accessor :enabled, :silence_archived_channel_exceptions

    def initialize
      # Default values
      @enabled = true
      @sandbox_default_behavior = :noop
      @max_inline_file_size = DEFAULT_MAX_INLINE_FILE_SIZE
      @max_async_file_upload_size = DEFAULT_MAX_ASYNC_FILE_UPLOAD_SIZE
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

    # Maximum file size to serialize directly to job payload (avoids sync Slack upload).
    # Files smaller than this are inlined; larger files are uploaded to Slack first.
    # Default: 512 KB (conservative for Redis memory)
    attr_reader :max_inline_file_size

    def max_inline_file_size=(value)
      validate_max_inline_file_size!(value)
      @max_inline_file_size = value
    end

    # Maximum total file size allowed for async uploads.
    # Set to nil to disable (only Slack's 1 GB per-file limit applies).
    # Files exceeding this raise an error immediately to avoid blocking web processes.
    # Default: 25 MB
    attr_reader :max_async_file_upload_size

    def max_async_file_upload_size=(value)
      validate_max_async_file_upload_size!(value)
      @max_async_file_upload_size = value
    end

    private

    def validate_max_inline_file_size!(value)
      return if value.nil? || (value.is_a?(Integer) && value >= 0)

      raise ArgumentError, "max_inline_file_size must be a non-negative integer, got: #{value.inspect}"
    end

    def validate_max_async_file_upload_size!(value)
      return if value.nil? # nil means disabled

      raise ArgumentError, "max_async_file_upload_size must be a non-negative integer or nil, got: #{value.inspect}" unless value.is_a?(Integer) && value >= 0

      return unless value > SLACK_MAX_FILE_SIZE

      raise ArgumentError,
            "max_async_file_upload_size (#{value}) cannot exceed Slack's maximum file size (#{SLACK_MAX_FILE_SIZE} bytes / 1 GB)"
    end

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
