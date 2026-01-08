# frozen_string_literal: true

RSpec.describe SlackSender::Util do
  describe ".parse_retry_delay_from_exception" do
    subject(:result) { described_class.parse_retry_delay_from_exception(exception) }

    context "with NotInChannel exception" do
      let(:exception) { Slack::Web::Api::Errors::NotInChannel.new("not_in_channel") }

      it { is_expected.to eq(:discard) }
    end

    context "with ChannelNotFound exception" do
      let(:exception) { Slack::Web::Api::Errors::ChannelNotFound.new("channel_not_found") }

      it { is_expected.to eq(:discard) }
    end

    context "with exception containing Retry-After header" do
      let(:exception) do
        error = Slack::Web::Api::Errors::TooManyRequestsError.new(double(
                                                                    code: 429,
                                                                    headers: { "Retry-After" => "30" },
                                                                  ))
        allow(error).to receive(:response_headers).and_return({ "Retry-After" => "30" })
        error
      end

      it { is_expected.to eq(30) }
    end

    context "with exception containing lowercase retry-after header" do
      let(:exception) do
        error = StandardError.new("rate limited")
        allow(error).to receive(:response_headers).and_return({ "retry-after" => "45" })
        error
      end

      it { is_expected.to eq(45) }
    end

    context "with exception with response_headers but no Retry-After" do
      let(:exception) do
        error = StandardError.new("some error")
        allow(error).to receive(:response_headers).and_return({ "X-Other-Header" => "value" })
        error
      end

      it { is_expected.to be_nil }
    end

    context "with exception with empty response_headers" do
      let(:exception) do
        error = StandardError.new("some error")
        allow(error).to receive(:response_headers).and_return({})
        error
      end

      it { is_expected.to be_nil }
    end

    context "with exception with non-Hash response_headers" do
      let(:exception) do
        error = StandardError.new("some error")
        allow(error).to receive(:response_headers).and_return(nil)
        error
      end

      it { is_expected.to be_nil }
    end

    context "with exception that does not respond to response_headers" do
      let(:exception) { StandardError.new("generic error") }

      it { is_expected.to be_nil }
    end

    context "with other Slack API error" do
      let(:exception) { Slack::Web::Api::Errors::SlackError.new("some_other_error") }

      it { is_expected.to be_nil }
    end
  end
end
