# frozen_string_literal: true

module SlackOutbox
  class HealthInsurance < Base
    CHANNELS = {}.freeze

    private

    # Overridable configuration methods
    def slack_token = ENV.fetch("HI_SLACK_BOT_API_TOKEN")
    # def dev_channel = CHANNELS[:slack_development] # TODO: HealthInsurance needs a slack_development channel
  end
end

