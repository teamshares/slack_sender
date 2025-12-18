# frozen_string_literal: true

module SlackOutbox
  class NetworkPresident < Base
    CHANNELS = {
      slack_development: "C0784MN9JRJ",
      peer_network_financials: "peer-network-financials", # TODO: swap to correct channel ID
    }.freeze

    private

    # Overridable configuration methods
    def slack_token = ENV.fetch("SLACK_PRESIDENT_WORKSPACE_API_TOKEN")
    def dev_channel = CHANNELS[:slack_development]
  end
end

