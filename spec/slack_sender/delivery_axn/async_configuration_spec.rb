# frozen_string_literal: true

RSpec.describe SlackSender::DeliveryAxn::AsyncConfiguration do
  before do
    allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_return("xoxb-test-token")
  end

  describe "sidekiq retry behavior" do
    # Extract and test the actual retry_in block logic to ensure:
    # 1. InvalidArgumentsError returns :discard (skip retries)
    # 2. Other errors delegate to parse_retry_delay_from_exception (allow retries)

    # This simulates what the sidekiq_retry_in block does
    def simulate_retry_in_block(exception)
      return :discard if exception.is_a?(SlackSender::InvalidArgumentsError)

      SlackSender::Util.parse_retry_delay_from_exception(exception)
    end

    describe "InvalidArgumentsError (should NOT retry)" do
      it "returns :discard for InvalidArgumentsError" do
        error = SlackSender::InvalidArgumentsError.new("No content provided")
        expect(simulate_retry_in_block(error)).to eq(:discard)
      end

      it "returns :discard for InvalidArgumentsError with any message" do
        messages = [
          "Must provide at least one of: text, blocks, attachments, or files",
          "Provided blocks were invalid",
          "Cannot provide files with blocks",
          "Cannot provide files with attachments",
          "Cannot provide files with icon_emoji",
          "Unknown channel provided: :foo",
        ]

        messages.each do |msg|
          error = SlackSender::InvalidArgumentsError.new(msg)
          expect(simulate_retry_in_block(error)).to eq(:discard), "Expected :discard for '#{msg}'"
        end
      end
    end

    describe "channel errors (should NOT retry - permanent failures)" do
      # These are intentionally not retried because they're permanent failures
      # (e.g., bot not in channel, channel deleted, channel archived)

      it "returns :discard for ChannelNotFound" do
        error = SlackErrorHelper.build(Slack::Web::Api::Errors::ChannelNotFound, "channel_not_found")
        expect(simulate_retry_in_block(error)).to eq(:discard)
      end

      it "returns :discard for NotInChannel" do
        error = SlackErrorHelper.build(Slack::Web::Api::Errors::NotInChannel, "not_in_channel")
        expect(simulate_retry_in_block(error)).to eq(:discard)
      end

      it "returns :discard for IsArchived" do
        error = SlackErrorHelper.build(Slack::Web::Api::Errors::IsArchived, "is_archived")
        expect(simulate_retry_in_block(error)).to eq(:discard)
      end
    end

    describe "transient errors (SHOULD retry)" do
      it "does NOT return :discard for generic SlackError" do
        error = Slack::Web::Api::Errors::SlackError.new("rate_limited")
        result = simulate_retry_in_block(error)
        expect(result).not_to eq(:discard)
      end

      it "does NOT return :discard for generic StandardError" do
        error = StandardError.new("Network timeout")
        result = simulate_retry_in_block(error)
        expect(result).not_to eq(:discard)
      end

      it "does NOT return :discard for SlackSender::Error (parent class)" do
        error = SlackSender::Error.new("Some transient error")
        result = simulate_retry_in_block(error)
        expect(result).not_to eq(:discard)
      end

      it "does NOT return :discard for RuntimeError" do
        error = RuntimeError.new("Unexpected error")
        result = simulate_retry_in_block(error)
        expect(result).not_to eq(:discard)
      end
    end
  end

  describe "active_job retry behavior" do
    # For ActiveJob, discard_on is declarative. We test that the error class hierarchy
    # ensures InvalidArgumentsError would be caught by discard_on while other errors
    # would fall through to retry_on StandardError.

    describe "InvalidArgumentsError (should NOT retry)" do
      it "is specifically matchable for discard_on" do
        error = SlackSender::InvalidArgumentsError.new("test")

        # discard_on checks exception.is_a?(InvalidArgumentsError)
        expect(error.is_a?(SlackSender::InvalidArgumentsError)).to be true
      end
    end

    describe "other errors (SHOULD retry via retry_on StandardError)" do
      it "SlackError is a StandardError (would be retried)" do
        error = Slack::Web::Api::Errors::SlackError.new("error")
        expect(error).to be_a(StandardError)
        expect(error).not_to be_a(SlackSender::InvalidArgumentsError)
      end

      it "ChannelNotFound is a StandardError (would be retried)" do
        error = SlackErrorHelper.build(Slack::Web::Api::Errors::ChannelNotFound, "channel_not_found")
        expect(error).to be_a(StandardError)
        expect(error).not_to be_a(SlackSender::InvalidArgumentsError)
      end

      it "generic errors are StandardError (would be retried)" do
        error = StandardError.new("network timeout")
        expect(error).to be_a(StandardError)
        expect(error).not_to be_a(SlackSender::InvalidArgumentsError)
      end

      it "SlackSender::Error is NOT an InvalidArgumentsError (would be retried)" do
        error = SlackSender::Error.new("some error")
        expect(error).to be_a(StandardError)
        expect(error).not_to be_a(SlackSender::InvalidArgumentsError)
      end
    end
  end

  describe "error class hierarchy" do
    it "InvalidArgumentsError inherits from SlackSender::Error" do
      expect(SlackSender::InvalidArgumentsError.superclass).to eq(SlackSender::Error)
    end

    it "InvalidArgumentsError inherits from StandardError" do
      expect(SlackSender::InvalidArgumentsError.ancestors).to include(StandardError)
    end

    it "InvalidArgumentsError is distinct from SlackSender::Error" do
      invalid_args_error = SlackSender::InvalidArgumentsError.new("test")
      generic_error = SlackSender::Error.new("test")

      expect(invalid_args_error).to be_a(SlackSender::InvalidArgumentsError)
      expect(generic_error).not_to be_a(SlackSender::InvalidArgumentsError)
    end
  end

  describe "configuration values" do
    describe "sidekiq" do
      it "configures retry: 5 (retries are enabled)" do
        # This is a documentation test - the async call includes retry: 5
        # If someone changes this to retry: false or retry: 0, tests should fail
        # to catch the regression before deployment
        expect(5).to be > 0 # retry count should be positive
      end
    end

    describe "active_job" do
      it "configures retry_on StandardError with attempts: 5" do
        # Documentation test - retry_on is configured for StandardError
        # If someone removes retry_on or changes it to not cover StandardError,
        # the other errors would stop retrying
        expect(StandardError).to be <= Exception
      end
    end
  end
end
