# frozen_string_literal: true

RSpec.describe SlackOutbox::NetworkPresident do
  let(:client_dbl) { instance_double(::Slack::Web::Client) }

  before do
    allow(::Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "123" })
  end

  describe "configuration" do
    before do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(false)
      # Stub the ENV fetch since this token may not exist in test env
      allow(ENV).to receive(:fetch).with("SLACK_PRESIDENT_WORKSPACE_API_TOKEN").and_return("xoxb-test-token")
    end

    it "uses SLACK_PRESIDENT_WORKSPACE_API_TOKEN for slack_token" do
      expect(::Slack::Web::Client).to receive(:new).with(hash_including(token: "xoxb-test-token"))

      described_class.call(channel: :slack_development, text: "test")
    end

    it "uses slack_development as dev_channel" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: described_class::CHANNELS[:slack_development]),
      )

      described_class.call(channel: "C_PROD_CHANNEL", text: "test")
    end
  end

  describe "CHANNELS" do
    it { expect(described_class::CHANNELS).to include(:slack_development) }
    it { expect(described_class::CHANNELS).to include(:peer_network_financials) }
  end
end

