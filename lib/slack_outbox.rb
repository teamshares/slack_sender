# frozen_string_literal: true

require_relative "slack_outbox/version"
require_relative "slack_outbox/configuration"
require_relative "slack_outbox/base"
require_relative "slack_outbox/file_wrapper"
require_relative "slack_outbox/os"
require_relative "slack_outbox/mfp"
require_relative "slack_outbox/network_president"
require_relative "slack_outbox/health_insurance"

module SlackOutbox
  class Error < StandardError; end
end

class SlackOutbox
  class << self
    def deliver(**kwargs)
      implementor.call_async(**kwargs)
      true
    end

    def deliver!(**kwargs)
      implementor.call!(**kwargs).thread_ts
    end

    private

    def implementor = SlackOutbox::OS
  end
end

class SlackOutbox::Mfp < SlackOutbox
  def self.implementor = SlackOutbox::Mfp
end

class SlackOutbox::NetworkPresident < SlackOutbox
  def self.implementor = SlackOutbox::NetworkPresident
end

class SlackOutbox::HealthInsurance < SlackOutbox
  def self.implementor = SlackOutbox::HealthInsurance
end
