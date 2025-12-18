# frozen_string_literal: true

module SlackOutbox
  class Configuration
    attr_writer :error_notifier

    def in_production=(value)
      @in_production = value
    end

    def in_production?
      return @in_production unless @in_production.nil?

      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.production?
      else
        false
      end
    end

    def error_notifier
      @error_notifier
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

