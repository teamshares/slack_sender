# frozen_string_literal: true

RSpec.describe SlackSender::Util do
  describe ".blank_text_only?" do
    subject(:result) { described_class.blank_text_only?(kwargs) }

    context "when text is blank string and no other content" do
      let(:kwargs) { { text: "" } }

      it { is_expected.to be true }
    end

    context "when text is whitespace-only string and no other content" do
      let(:kwargs) { { text: "   " } }

      it { is_expected.to be true }
    end

    context "when text is present" do
      let(:kwargs) { { text: "hello" } }

      it { is_expected.to be false }
    end

    context "when text key is missing" do
      let(:kwargs) { { blocks: [] } }

      it { is_expected.to be false }
    end

    context "when text is blank but blocks present" do
      let(:kwargs) { { text: "", blocks: [{ type: "section" }] } }

      it { is_expected.to be false }
    end

    context "when text is blank but attachments present" do
      let(:kwargs) { { text: "", attachments: [{ color: "good" }] } }

      it { is_expected.to be false }
    end

    context "when text is blank but files present" do
      let(:kwargs) { { text: "", files: [StringIO.new("content")] } }

      it { is_expected.to be false }
    end

    context "when text is blank but file (singular) present" do
      let(:kwargs) { { text: "", file: StringIO.new("content") } }

      it { is_expected.to be false }
    end

    context "when text is nil (not a String)" do
      let(:kwargs) { { text: nil } }

      it { is_expected.to be false }
    end

    context "when text is blank with empty arrays for other content" do
      let(:kwargs) { { text: "", blocks: [], attachments: [], files: [] } }

      it { is_expected.to be true }
    end
  end

  describe ".extract_needed_scope" do
    subject(:result) { described_class.extract_needed_scope(exception) }

    let(:response_body) { double("body", needed: nil, response_metadata: nil) }
    let(:response_env) { { response_headers: {} } }
    let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
    let(:exception) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

    context "when needed scope is in response.body.needed" do
      let(:response_body) { double("body", needed: "chat:write", response_metadata: nil) }

      it { is_expected.to eq("chat:write") }
    end

    context "when needed scope is in response_metadata" do
      before do
        allow(exception).to receive(:response_metadata).and_return({ "needed" => "files:write" })
      end

      it { is_expected.to eq("files:write") }
    end

    context "when needed scope is in x-accepted-oauth-scopes header" do
      let(:response_env) { { response_headers: { "x-accepted-oauth-scopes" => "channels:read" } } }

      it { is_expected.to eq("channels:read") }
    end

    context "when needed scope is not found anywhere" do
      it { is_expected.to be_nil }
    end

    context "when response.body supports hash access for needed" do
      let(:response_body) { double("body", needed: nil, response_metadata: nil) }

      before do
        allow(response_body).to receive(:try).with(:needed).and_return(nil)
        allow(response_body).to receive(:try).with(:[], "needed").and_return("users:read")
      end

      it { is_expected.to eq("users:read") }
    end
  end

  describe ".missing_scope_error_message" do
    subject(:result) { described_class.missing_scope_error_message(exception) }

    let(:response_body) { double("body", needed: nil, response_metadata: nil) }
    let(:response_env) { { response_headers: {} } }
    let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
    let(:exception) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

    context "when needed scope is found" do
      let(:response_body) { double("body", needed: "files:write", response_metadata: nil) }

      it "includes the scope name" do
        expect(result).to include("files:write")
      end

      it "includes guidance to add the scope" do
        expect(result).to include("Add this scope to your Slack app")
      end
    end

    context "when needed scope is not found" do
      it "returns a generic message" do
        expect(result).to include("Check your Slack app's OAuth scopes")
      end
    end
  end

  describe ".parse_retry_delay_from_exception" do
    subject(:result) { described_class.parse_retry_delay_from_exception(exception) }

    context "with NotInChannel exception" do
      let(:exception) { SlackErrorHelper.build(Slack::Web::Api::Errors::NotInChannel, "not_in_channel") }

      it { is_expected.to eq(:discard) }
    end

    context "with ChannelNotFound exception" do
      let(:exception) { SlackErrorHelper.build(Slack::Web::Api::Errors::ChannelNotFound, "channel_not_found") }

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
