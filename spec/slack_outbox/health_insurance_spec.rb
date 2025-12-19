# frozen_string_literal: true

RSpec.describe SlackOutbox::HealthInsurance do
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "123" })
    allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
    # Stub the ENV fetch since this token may not exist in test env
    allow(ENV).to receive(:fetch).with("HI_SLACK_BOT_API_TOKEN").and_return("xoxb-hi-token")
  end

  describe "configuration" do
    it "uses HI_SLACK_BOT_API_TOKEN for slack_token" do
      expect(Slack::Web::Client).to receive(:new).with(hash_including(token: "xoxb-hi-token"))

      described_class.call(channel: "C123", text: "test")
    end
  end

  describe "CHANNELS" do
    it { expect(described_class::CHANNELS).to eq({}) }
  end
end
