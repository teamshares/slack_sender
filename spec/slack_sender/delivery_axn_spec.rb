# frozen_string_literal: true

require "csv"

RSpec.describe SlackSender::DeliveryAxn do
  let(:profile) { build(:profile, user_groups: { slack_development: "SLACK_DEV_TEST_USER_GROUP_HANDLE" }) }
  let(:action_class) { SlackSender::DeliveryAxn }
  let(:channel) { "C01H3KU3B9P" }
  let(:text) { "Hello, World!" }
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "1234567890.123456" })
    # Stub the ENV fetch since this token may not exist in test env
    allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_return("xoxb-test-token")
  end

  describe "expects" do
    describe "channel validation" do
      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
      end

      context "with validate_known_channel: true and known channel name" do
        subject(:result) { action_class.call(profile:, channel: "slack_development", validate_known_channel: true, text:) }

        it "validates channel exists in profile and resolves to channel ID" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: profile.channels[:slack_development]),
          )

          expect(result).to be_ok
        end
      end

      context "with validate_known_channel: true and unknown channel" do
        subject(:result) { action_class.call(profile:, channel: "unknown_channel", validate_known_channel: true, text:) }

        it "fails with validation error" do
          expect(result).not_to be_ok
          expect(result.error).to include("Unknown channel provided: :unknown_channel")
        end
      end

      context "with validate_known_channel: false" do
        subject(:result) { action_class.call(profile:, channel: "C123456", validate_known_channel: false, text:) }

        it "uses the channel ID directly without validation" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: "C123456"),
          )

          expect(result).to be_ok
        end
      end

      context "with validate_known_channel default (false)" do
        subject(:result) { action_class.call(profile:, channel: "C123456", text:) }

        it "uses the channel ID directly without validation" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: "C123456"),
          )

          expect(result).to be_ok
        end
      end
    end

    describe "text preprocessing" do
      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
      end

      context "with markdown text" do
        subject(:result) { action_class.call(profile:, channel:, text: "Hello *world*") }

        it "formats text using Slack markdown formatting" do
          expect(Slack::Messages::Formatting).to receive(:markdown).with("Hello *world*").and_call_original
          expect(result).to be_ok
        end
      end

      context "with nil text" do
        subject(:result) { action_class.call(profile:, channel:, text: nil) }

        it "fails without other content" do
          expect(result).not_to be_ok
          expect(result.error).to eq("Must provide at least one of: text, blocks, attachments, or files")
        end
      end
    end

    describe "icon_emoji preprocessing" do
      subject(:result) { action_class.call(profile:, channel:, text:, icon_emoji:) }

      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
      end

      context "with emoji without colons" do
        let(:icon_emoji) { "robot" }

        it "wraps emoji with colons" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(icon_emoji: ":robot:"),
          )
          expect(result).to be_ok
        end
      end

      context "with emoji with colons" do
        let(:icon_emoji) { ":robot:" }

        it "does not duplicate colons" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(icon_emoji: ":robot:"),
          )
          expect(result).to be_ok
        end
      end

      context "with nil emoji" do
        let(:icon_emoji) { nil }

        it "omits icon_emoji parameter" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_excluding(:icon_emoji),
          )
          expect(result).to be_ok
        end
      end
    end
  end

  describe "validation (before block)" do
    context "when content is blank" do
      subject(:result) { action_class.call(profile:, channel:) }

      it "fails with error message" do
        expect(result).not_to be_ok
        expect(result.error).to eq("Must provide at least one of: text, blocks, attachments, or files")
      end
    end

    context "when text is explicitly provided but blank (and no other content keys are provided)" do
      subject(:result) { action_class.call(profile:, channel:, text:) }

      let(:text) { "" }

      it "succeeds and does not call Slack" do
        expect(client_dbl).not_to receive(:chat_postMessage)
        expect(client_dbl).not_to receive(:files_upload_v2)

        expect(result).to be_ok
        expect(result.thread_ts).to be_nil
      end
    end

    context "when blocks are invalid" do
      subject(:result) { action_class.call(profile:, channel:, blocks:) }

      context "with empty array" do
        let(:blocks) { [] }

        it "fails since blocks are empty" do
          expect(result).not_to be_ok
        end
      end

      context "with blocks missing type key" do
        let(:blocks) { [{ text: "hello" }] }

        it "fails with error message" do
          expect(result).not_to be_ok
          expect(result.error).to eq("Provided blocks were invalid")
        end
      end

      context "with valid blocks" do
        let(:blocks) { [{ type: "section", text: { type: "mrkdwn", text: "hello" } }] }

        it "succeeds" do
          expect(result).to be_ok
        end
      end

      context "with blocks using string keys" do
        let(:blocks) { [{ "type" => "section", "text" => { "type" => "mrkdwn", "text" => "hello" } }] }

        it "succeeds" do
          expect(result).to be_ok
        end
      end
    end

    context "when files are provided" do
      let(:file) { StringIO.new("file content") }
      let(:files) { [file] }

      before do
        allow(client_dbl).to receive(:files_upload_v2).and_return({ "files" => [{ "id" => "f_123" }] })
        allow(client_dbl).to receive(:files_info).and_return({
                                                               "file" => { "shares" => { "public" => { channel => [{ "ts" => "123.456" }] } } },
                                                             })
      end

      context "with blocks" do
        subject(:result) { action_class.call(profile:, channel:, files:, blocks: [{ type: "section" }]) }

        it "fails with error message" do
          expect(result).not_to be_ok
          expect(result.error).to eq("Cannot provide files with blocks")
        end
      end

      context "with attachments" do
        subject(:result) { action_class.call(profile:, channel:, files:, attachments: [{ color: "good" }]) }

        it "fails with error message" do
          expect(result).not_to be_ok
          expect(result.error).to eq("Cannot provide files with attachments")
        end
      end

      context "with icon_emoji" do
        subject(:result) { action_class.call(profile:, channel:, files:, icon_emoji: "robot") }

        it "fails with error message" do
          expect(result).not_to be_ok
          expect(result.error).to eq("Cannot provide files with icon_emoji")
        end
      end

      context "with text only" do
        subject(:result) { action_class.call(profile:, channel:, files:, text:) }

        before do
          allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
        end

        it "succeeds" do
          expect(result).to be_ok
        end
      end
    end
  end

  describe "#call" do
    describe "posting messages" do
      subject(:result) { action_class.call(profile:, channel:, text:, blocks:, attachments:, icon_emoji:, thread_ts:) }

      let(:blocks) { nil }
      let(:attachments) { nil }
      let(:icon_emoji) { nil }
      let(:thread_ts) { nil }

      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(sandbox_mode?)
      end

      context "when not in sandbox mode (production)" do
        let(:sandbox_mode?) { false }

        it "posts to actual channel with actual text" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel:, text:),
          )

          expect(result).to be_ok
        end

        it "exposes thread_ts from response" do
          expect(result.thread_ts).to eq("1234567890.123456")
        end
      end

      context "when in sandbox mode (not production)" do
        let(:sandbox_mode?) { true }

        it "posts to sandbox channel with wrapped text" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(
              channel: profile.sandbox_channel,
              text: a_string_matching(/:construction:.*This message would have been sent to.*#{channel}.*in production/m),
            ),
          )

          expect(result).to be_ok
        end

        context "with custom sandbox channel message_prefix" do
          let(:profile) { build(:profile, sandbox: { channel: { replace_with: "C01H3KU3B9P", message_prefix: "🚧 DEV MODE: Would have gone to %s 🚧" } }) }

          it "uses custom prefix and formats channel_display correctly" do
            expect(client_dbl).to receive(:chat_postMessage).with(
              hash_including(
                channel: profile.sandbox_channel,
                text: a_string_matching(/🚧 DEV MODE: Would have gone to.*#{channel}.*🚧/m),
              ),
            )

            expect(result).to be_ok
          end
        end
      end
    end

    describe "uploading files" do
      subject(:result) { action_class.call(profile:, channel:, files:, text: "File attached") }

      let(:file) { Tempfile.new(["test", ".txt"]) }
      let(:files) { [file] }

      before do
        file.write("file content")
        file.rewind
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
        allow(client_dbl).to receive(:files_upload_v2).and_return({ "files" => [{ "id" => "f_123" }] })
        allow(client_dbl).to receive(:files_info).and_return({
                                                               "file" => { "shares" => { "public" => { channel => [{ "ts" => "123.456" }] } } },
                                                             })
      end

      after do
        file.close
        file.unlink
      end

      it "calls files_upload_v2" do
        expect(client_dbl).to receive(:files_upload_v2).with(
          files: [hash_including(content: "file content")],
          channel:,
          initial_comment: "File attached",
        )

        expect(result).to be_ok
      end

      it "exposes thread_ts from file info" do
        expect(result.thread_ts).to eq("123.456")
      end

      context "with single file object not wrapped in array" do
        let(:csv_file) do
          csv_content = CSV.generate(headers: ["Header 1", "Header 2", "Header 3"], write_headers: true) do |csv|
            csv << ["Value 1", "Value 2", "Value 3"]
            csv << ["Value 1", "Value 2", "Value 3"]
          end
          csv = StringIO.new(csv_content)
          csv.define_singleton_method(:original_filename) { "test.csv" }
          csv
        end
        let(:files) { csv_file }

        it "treats single file object as one file, not multiple files from lines" do
          expect(client_dbl).to receive(:files_upload_v2) do |args|
            # Verify only one file is uploaded, not multiple files from CSV lines
            expect(args[:files].length).to eq(1)
            expect(args[:files].first[:filename]).to eq("test.csv")
            expect(args[:files].first[:content]).to include("Header 1", "Header 2", "Header 3")
            { "files" => [{ "id" => "f_123" }] }
          end

          expect(result).to be_ok
        end
      end

      context "with private channel shares" do
        before do
          allow(client_dbl).to receive(:files_info).and_return({
                                                                 "file" => { "shares" => { "private" => { channel => [{ "ts" => "private.ts" }] } } },
                                                               })
        end

        it "finds thread_ts from private shares" do
          expect(result.thread_ts).to eq("private.ts")
        end
      end

      context "when IsArchived error occurs during file upload" do
        before do
          allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
          allow(client_dbl).to receive(:files_upload_v2).and_raise(
            SlackErrorHelper.build(Slack::Web::Api::Errors::IsArchived, "is_archived"),
          )
        end

        context "when config.silence_archived_channel_exceptions is false" do
          subject(:result) { action_class.call!(profile:, channel:, files:, text:) }

          before do
            allow(SlackSender.config).to receive(:silence_archived_channel_exceptions).and_return(false)
          end

          it "logs warning and re-raises" do
            expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED.*Is Archived/m)
            expect { result }.to raise_error(Slack::Web::Api::Errors::IsArchived)
          end
        end

        context "when config.silence_archived_channel_exceptions is true" do
          before do
            allow(SlackSender.config).to receive(:silence_archived_channel_exceptions).and_return(true)
          end

          it "succeeds with done message" do
            result_obj = action_class.call(profile:, channel:, files:, text:)
            expect(result_obj).to be_ok
            expect(result_obj.success).to eq("Failed successfully: ignoring 'is archived' error per config")
          end
        end
      end
    end

    describe "error handling" do
      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
      end

      shared_examples "channel error with warning" do |error_class, error_code, error_text|
        subject(:result) { action_class.call!(profile:, channel:, text:) }

        before do
          allow(client_dbl).to receive(:chat_postMessage).and_raise(
            SlackErrorHelper.build(error_class, error_code),
          )
        end

        it "logs warning and re-raises" do
          expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED.*#{error_text}/m)
          expect(client_dbl).to receive(:chat_postMessage).once
          expect { result }.to raise_error(error_class)
        end
      end

      context "when NotInChannel error occurs" do
        include_examples "channel error with warning",
                         Slack::Web::Api::Errors::NotInChannel, "not_in_channel", "Not In Channel"
      end

      context "when ChannelNotFound error occurs" do
        include_examples "channel error with warning",
                         Slack::Web::Api::Errors::ChannelNotFound, "channel_not_found", "Channel Not Found"
      end

      context "when IsArchived error occurs" do
        subject(:result) { action_class.call!(profile:, channel:, text:) }

        context "when config.silence_archived_channel_exceptions is false" do
          before do
            allow(SlackSender.config).to receive(:silence_archived_channel_exceptions).and_return(false)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(
              SlackErrorHelper.build(Slack::Web::Api::Errors::IsArchived, "is_archived"),
            )
          end

          it "logs warning and re-raises" do
            expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED.*Is Archived/m)
            expect { result }.to raise_error(Slack::Web::Api::Errors::IsArchived)
          end
        end

        context "when config.silence_archived_channel_exceptions is true" do
          before do
            allow(SlackSender.config).to receive(:silence_archived_channel_exceptions).and_return(true)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(
              SlackErrorHelper.build(Slack::Web::Api::Errors::IsArchived, "is_archived"),
            )
          end

          it "succeeds with done message" do
            result_obj = action_class.call(profile:, channel:, text:)
            expect(result_obj).to be_ok
            expect(result_obj.success).to eq("Failed successfully: ignoring 'is archived' error per config")
          end
        end

        context "when config.silence_archived_channel_exceptions is nil" do
          before do
            allow(SlackSender.config).to receive(:silence_archived_channel_exceptions).and_return(nil)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(
              SlackErrorHelper.build(Slack::Web::Api::Errors::IsArchived, "is_archived"),
            )
          end

          it "logs warning and re-raises" do
            expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED.*Is Archived/m)
            expect { result }.to raise_error(Slack::Web::Api::Errors::IsArchived)
          end
        end
      end

      describe "error message parsing" do
        subject(:result) { action_class.call(profile:, channel:, text:) }

        context "when SlackError has hash response" do
          let(:error_response) do
            {
              "ok" => false,
              "error" => "invalid_arguments",
              "needed" => "channel",
              "provided" => "text",
              "response_metadata" => {
                "messages" => ["Invalid channel provided", "Channel does not exist"],
              },
            }
          end

          before do
            slack_error = Slack::Web::Api::Errors::SlackError.new("invalid_arguments")
            allow(slack_error).to receive(:response).and_return(error_response)
            allow(slack_error).to receive(:error).and_return("invalid_arguments")
            allow(slack_error).to receive(:response_metadata).and_return(nil)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
          end

          it "parses error message with all fields" do
            expect(result).not_to be_ok
            expect(result.error).to include("invalid_arguments")
            expect(result.error).to include("needed=channel")
            expect(result.error).to include("provided=text")
            expect(result.error).to include("Invalid channel provided; Channel does not exist")
          end
        end

        context "when SlackError has Faraday::Response object" do
          let(:faraday_response) do
            double("Faraday::Response", body: {
                     "ok" => false,
                     "error" => "invalid_arguments",
                     "needed" => "channel",
                     "provided" => "text",
                   })
          end

          before do
            slack_error = Slack::Web::Api::Errors::SlackError.new("invalid_arguments")
            allow(slack_error).to receive(:response).and_return(faraday_response)
            allow(slack_error).to receive(:error).and_return("invalid_arguments")
            allow(slack_error).to receive(:response_metadata).and_return(nil)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
          end

          it "extracts body from Faraday::Response and parses error message" do
            expect(result).not_to be_ok
            expect(result.error).to include("invalid_arguments")
            expect(result.error).to include("needed=channel")
            expect(result.error).to include("provided=text")
          end
        end

        context "when SlackError has nil response" do
          before do
            slack_error = Slack::Web::Api::Errors::SlackError.new("unknown_error")
            allow(slack_error).to receive(:response).and_return(nil)
            allow(slack_error).to receive(:error).and_return("unknown_error")
            allow(slack_error).to receive(:response_metadata).and_return(nil)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
          end

          it "handles nil response gracefully" do
            expect(result).not_to be_ok
            expect(result.error).to eq("unknown_error")
          end
        end

        context "when SlackError has response_metadata on exception" do
          let(:response_metadata) do
            {
              "messages" => ["Custom error message from metadata"],
            }
          end

          before do
            slack_error = Slack::Web::Api::Errors::SlackError.new("invalid_arguments")
            allow(slack_error).to receive(:response).and_return({})
            allow(slack_error).to receive(:error).and_return("invalid_arguments")
            allow(slack_error).to receive(:response_metadata).and_return(response_metadata)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
          end

          it "uses response_metadata from exception when available" do
            expect(result).not_to be_ok
            expect(result.error).to include("invalid_arguments")
            expect(result.error).to include("Custom error message from metadata")
          end
        end

        context "when SlackError has extra fields in response" do
          let(:error_response) do
            {
              "ok" => false,
              "error" => "invalid_arguments",
              "custom_field" => "custom_value",
              "another_field" => 123,
            }
          end

          before do
            slack_error = Slack::Web::Api::Errors::SlackError.new("invalid_arguments")
            allow(slack_error).to receive(:response).and_return(error_response)
            allow(slack_error).to receive(:error).and_return("invalid_arguments")
            allow(slack_error).to receive(:response_metadata).and_return(nil)
            allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
          end

          it "includes extra fields in error message" do
            expect(result).not_to be_ok
            expect(result.error).to include("invalid_arguments")
            expect(result.error).to include("custom_field")
            expect(result.error).to include("another_field")
          end
        end
      end
    end
  end

  describe "InvalidArgumentsError" do
    describe "raises InvalidArgumentsError for validation failures" do
      shared_examples "raises InvalidArgumentsError" do |error_message|
        it "raises InvalidArgumentsError when using call!" do
          expect { action_class.call!(profile:, **call_args) }.to raise_error(SlackSender::InvalidArgumentsError, error_message)
        end

        it "returns failed result with error message when using call" do
          result = action_class.call(profile:, **call_args)
          expect(result).not_to be_ok
          expect(result.error).to eq(error_message)
        end

        it "captures the exception on the result" do
          result = action_class.call(profile:, **call_args)
          # The exception is either InvalidArgumentsError directly or PreprocessingError wrapping it
          expect(result.exception).to be_a(StandardError)
        end
      end

      context "when no content is provided" do
        let(:call_args) { { channel: } }

        include_examples "raises InvalidArgumentsError", "Must provide at least one of: text, blocks, attachments, or files"
      end

      context "when blocks are invalid" do
        let(:call_args) { { channel:, blocks: [{ text: "missing type key" }] } }

        include_examples "raises InvalidArgumentsError", "Provided blocks were invalid"
      end

      context "when files provided with blocks" do
        let(:file) { StringIO.new("content") }
        let(:call_args) { { channel:, files: [file], blocks: [{ type: "section" }] } }

        before do
          allow(client_dbl).to receive(:files_upload_v2)
          allow(client_dbl).to receive(:files_info)
        end

        include_examples "raises InvalidArgumentsError", "Cannot provide files with blocks"
      end

      context "when files provided with attachments" do
        let(:file) { StringIO.new("content") }
        let(:call_args) { { channel:, files: [file], attachments: [{ color: "good" }] } }

        before do
          allow(client_dbl).to receive(:files_upload_v2)
          allow(client_dbl).to receive(:files_info)
        end

        include_examples "raises InvalidArgumentsError", "Cannot provide files with attachments"
      end

      context "when files provided with icon_emoji" do
        let(:file) { StringIO.new("content") }
        let(:call_args) { { channel:, files: [file], icon_emoji: "robot" } }

        before do
          allow(client_dbl).to receive(:files_upload_v2)
          allow(client_dbl).to receive(:files_info)
        end

        include_examples "raises InvalidArgumentsError", "Cannot provide files with icon_emoji"
      end

      context "when unknown channel with validate_known_channel: true" do
        let(:call_args) { { channel: "unknown_channel", validate_known_channel: true, text: } }

        it "raises InvalidArgumentsError (wrapped in PreprocessingError) when using call!" do
          # Channel validation happens in preprocess, so it's wrapped in PreprocessingError
          expect { action_class.call!(profile:, **call_args) }.to raise_error(Axn::ContractViolation::PreprocessingError) do |error|
            expect(error.cause).to be_a(SlackSender::InvalidArgumentsError)
            expect(error.cause.message).to include("Unknown channel provided: :unknown_channel")
          end
        end

        it "returns failed result with unwrapped error message when using call" do
          result = action_class.call(profile:, **call_args)
          expect(result).not_to be_ok
          expect(result.error).to include("Unknown channel provided: :unknown_channel")
        end
      end
    end

    describe "error class hierarchy" do
      it "inherits from SlackSender::Error" do
        expect(SlackSender::InvalidArgumentsError.superclass).to eq(SlackSender::Error)
      end

      it "inherits from StandardError" do
        expect(SlackSender::InvalidArgumentsError.ancestors).to include(StandardError)
      end
    end
  end

  describe "text_to_use" do
    subject(:result) { action_class.call(profile:, channel:, text: "Line 1\nLine 2\nLine 3") }

    before do
      allow(SlackSender.config).to receive(:sandbox_mode?).and_return(true)
    end

    it "wraps each line with quote formatting" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(
          text: a_string_matching(/> Line 1.*> Line 2.*> Line 3/m),
        ),
      )

      expect(result).to be_ok
    end

    context "with channel ID" do
      let(:channel) { "C123456" }

      it "replaces %s in dev_channel_redirect_prefix with channel link" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(
            text: a_string_matching(/:construction:.*This message would have been sent to.*<#C123456>.*in production/m),
          ),
        )

        expect(result).to be_ok
      end
    end

    context "with custom sandbox channel message_prefix" do
      let(:profile) { build(:profile, sandbox: { channel: { replace_with: "C01H3KU3B9P", message_prefix: "Test prefix with %s replacement" } }) }

      it "replaces %s with channel_display value" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(
            text: a_string_matching(/Test prefix with.*#{channel}.*replacement/m),
          ),
        )

        expect(result).to be_ok
      end
    end
  end

  describe "sandbox behavior" do
    before do
      allow(SlackSender.config).to receive(:sandbox_mode?).and_return(true)
    end

    describe "behavior :redirect" do
      let(:profile) { build(:profile, sandbox: { behavior: :redirect, channel: { replace_with: "C_SANDBOX" } }) }

      it "redirects message to sandbox channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C_SANDBOX"),
        )

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end

      it "adds prefix to message text" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(
            text: a_string_matching(/would have been sent to.*in production/i),
          ),
        )

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end
    end

    describe "behavior :noop" do
      let(:profile) { build(:profile, sandbox: { behavior: :noop }) }

      it "does not send message to Slack" do
        expect(client_dbl).not_to receive(:chat_postMessage)
        expect(client_dbl).not_to receive(:files_upload_v2)

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end

      it "logs the noop action" do
        expect(action_class).to receive(:info).with(/\[SANDBOX NOOP\].*Profile:.*Channel:.*Text:/i).at_least(:once)
        allow(action_class).to receive(:info)

        action_class.call(profile:, channel:, text:)
      end

      it "returns success message indicating noop" do
        result = action_class.call(profile:, channel:, text:)
        expect(result.success).to include("noop")
      end
    end

    describe "behavior :passthrough" do
      let(:profile) { build(:profile, sandbox: { behavior: :passthrough }) }

      it "sends message to the actual channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel:),
        )

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end

      it "does not modify the message text" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(text:),
        )

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end
    end

    describe "behavior resolution fallback" do
      context "when profile has no sandbox config" do
        let(:profile) { build(:profile, sandbox: {}) }

        it "uses config.sandbox_default_behavior" do
          allow(SlackSender.config).to receive(:sandbox_default_behavior).and_return(:noop)
          expect(client_dbl).not_to receive(:chat_postMessage)

          result = action_class.call(profile:, channel:, text:)
          expect(result).to be_ok
        end
      end

      context "when profile has channel.replace_with but no explicit behavior" do
        let(:profile) { build(:profile, sandbox: { channel: { replace_with: "C_INFERRED" } }) }

        it "infers :redirect behavior" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: "C_INFERRED"),
          )

          result = action_class.call(profile:, channel:, text:)
          expect(result).to be_ok
        end
      end
    end

    describe "when sandbox_mode? is false" do
      before do
        allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
      end

      let(:profile) { build(:profile, sandbox: { behavior: :noop }) }

      it "ignores sandbox config and sends to real channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel:, text:),
        )

        result = action_class.call(profile:, channel:, text:)
        expect(result).to be_ok
      end
    end
  end
end
