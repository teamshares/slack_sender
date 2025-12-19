# frozen_string_literal: true

module SlackOutbox
  class Mfp < Base
    CHANNELS = {
      slack_development: "C07QVBFRGC9",
    }.freeze

    private

    # Overridable configuration methods
    def slack_token = ENV.fetch("MFP_SLACK_WORKSPACE_API_TOKEN")
    def dev_channel = CHANNELS[:slack_development]
  end
end
