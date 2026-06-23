# frozen_string_literal: true

module SlackSender
  class Configuration
    # Validated instance settings via the upstream Axn::Configurable DSL (class flavor).
    # Only the simple settings are declared here; everything bespoke below stays hand-written.
    extend Axn::Configurable::Settings

    SUPPORTED_ASYNC_BACKENDS = %i[sidekiq active_job].freeze
    SUPPORTED_SANDBOX_BEHAVIORS = %i[noop redirect passthrough].freeze

    # Slack's hard limit per file (1 GB)
    SLACK_MAX_FILE_SIZE = 1_073_741_824

    # Default file size threshold for async uploads
    DEFAULT_MAX_ASYNC_FILE_UPLOAD_SIZE = 26_214_400 # 25 MB

    setting :enabled, default: true
    setting :silence_archived_channel_exceptions
    setting :sandbox_default_behavior, default: :noop, one_of: SUPPORTED_SANDBOX_BEHAVIORS

    # Whether to autoload files in app/slack_notifiers under the SlackNotifiers namespace.
    # When true (default): app/slack_notifiers/foo.rb defines SlackNotifiers::Foo
    # When false: app/slack_notifiers/foo.rb defines Foo (standard Rails behavior)
    setting :use_slack_notifiers_namespace, default: true

    attr_writer :sandbox_mode

    def initialize
      # Bespoke settings (not backed by the DSL) need their defaults set here.
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
