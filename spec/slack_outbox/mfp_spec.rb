# frozen_string_literal: true

RSpec.describe SlackOutbox::Mfp do
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "123" })
    # Stub the ENV fetch since this token may not exist in test env
    allow(ENV).to receive(:fetch).with("MFP_SLACK_WORKSPACE_API_TOKEN").and_return("xoxb-mfp-token")
  end

  describe "configuration" do
    before do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(false)
    end

    it "uses MFP_SLACK_WORKSPACE_API_TOKEN for slack_token" do
      expect(Slack::Web::Client).to receive(:new).with(hash_including(token: "xoxb-mfp-token"))

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
  end
end
