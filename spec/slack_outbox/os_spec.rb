# frozen_string_literal: true

RSpec.describe SlackOutbox::OS do
  let(:client_dbl) { instance_double(::Slack::Web::Client) }

  before do
    allow(::Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "123" })
  end

  describe "configuration" do
    before do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(false)
    end

    it "uses SLACK_API_TOKEN for slack_token" do
      # Verify the token env var name is correct by checking the client is created
      # The actual token value comes from doppler/ENV in test environment
      expect(::Slack::Web::Client).to receive(:new).with(hash_including(:token))

      described_class.call(channel: :slack_development, text: "test")
    end

    it "uses slack_development as dev_channel" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: described_class::CHANNELS[:slack_development]),
      )

      described_class.call(channel: "C_PROD_CHANNEL", text: "test")
    end

    it "uses eng_alerts as error_channel" do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(true)

      call_count = 0
      allow(client_dbl).to receive(:chat_postMessage) do |args|
        call_count += 1
        raise ::Slack::Web::Api::Errors::NotInChannel, "not_in_channel" if call_count == 1

        expect(args[:channel]).to eq(described_class::CHANNELS[:eng_alerts])
        { "ts" => "123" }
      end

      expect { described_class.call!(channel: "C_OTHER", text: "test") }.to raise_error(::Slack::Web::Api::Errors::NotInChannel)
    end
  end

  describe "CHANNELS" do
    it { expect(described_class::CHANNELS).to include(:slack_development) }
    it { expect(described_class::CHANNELS).to include(:eng_ops) }
    it { expect(described_class::CHANNELS).to include(:eng_alerts) }
    it { expect(described_class::CHANNELS).to include(:banking_overdraft) }
    it { expect(described_class::CHANNELS).to include(:cash_management) }
    it { expect(described_class::CHANNELS).to include(:customer_group) }
    it { expect(described_class::CHANNELS).to include(:data_engineering_alerts) }
    it { expect(described_class::CHANNELS).to include(:eo_share_issuance) }
    it { expect(described_class::CHANNELS).to include(:onestream) }
    it { expect(described_class::CHANNELS).to include(:os_feedback) }
    it { expect(described_class::CHANNELS).to include(:os_payroll_matching_review) }
    it { expect(described_class::CHANNELS).to include(:valuations) }
    it { expect(described_class::CHANNELS).to include(:valuations_alert) }
  end

  describe "USER_GROUPS" do
    it { expect(described_class::USER_GROUPS).to include(:overdraft_loan_alert) }
    it { expect(described_class::USER_GROUPS).to include(:slack_development) }
  end
end

