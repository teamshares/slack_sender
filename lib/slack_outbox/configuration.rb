# frozen_string_literal: true

module SlackOutbox
  class Configuration
    attr_writer :in_production

    def in_production?
      return @in_production unless @in_production.nil?

      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.production?
      else
        false
      end
    end

    attr_accessor :error_notifier
    attr_accessor :max_background_file_size
  end

  class << self
    def config = @config ||= Configuration.new

    def configure
      self.config ||= Configuration.new
      yield(config) if block_given?
    end
  end
end
