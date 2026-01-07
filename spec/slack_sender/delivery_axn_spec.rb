# frozen_string_literal: true

RSpec.describe SlackSender::DeliveryAxn do
  let(:profile) do
    SlackSender::Profile.new(
      token: "SLACK_API_TOKEN",
      dev_channel: "C01H3KU3B9P",
      error_channel: "C03F1DMJ4PM",
      channels: {
        slack_development: "C01H3KU3B9P",
        eng_alerts: "C03F1DMJ4PM",
      },
      user_groups: {
        slack_development: "SLACK_DEV_TEST_USER_GROUP_HANDLE",
      },
    )
  end
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
        allow(SlackSender.config).to receive(:in_production?).and_return(true)
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
        allow(SlackSender.config).to receive(:in_production?).and_return(true)
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
        allow(SlackSender.config).to receive(:in_production?).and_return(true)
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
          allow(SlackSender.config).to receive(:in_production?).and_return(true)
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
        allow(SlackSender.config).to receive(:in_production?).and_return(production?)
      end

      context "in production" do
        let(:production?) { true }

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

      context "not in production" do
        let(:production?) { false }

        it "posts to dev channel with wrapped text" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(
              channel: profile.channels[:slack_development],
              text: a_string_matching(/:construction:.*This message would have been sent to.*#{channel}.*in production/m),
            ),
          )

          expect(result).to be_ok
        end

        context "with custom dev_channel_redirect_prefix" do
          let(:profile) do
            SlackSender::Profile.new(
              token: "SLACK_API_TOKEN",
              dev_channel: "C01H3KU3B9P",
              error_channel: "C03F1DMJ4PM",
              channels: {
                slack_development: "C01H3KU3B9P",
                eng_alerts: "C03F1DMJ4PM",
              },
              user_groups: {
                slack_development: "SLACK_DEV_TEST_USER_GROUP_HANDLE",
              },
              dev_channel_redirect_prefix: "🚧 DEV MODE: Would have gone to %s 🚧",
            )
          end

          it "uses custom prefix and formats channel_display correctly" do
            expect(client_dbl).to receive(:chat_postMessage).with(
              hash_including(
                channel: profile.channels[:slack_development],
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
        allow(SlackSender.config).to receive(:in_production?).and_return(true)
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
          allow(client_dbl).to receive(:files_upload_v2).and_raise(
            Slack::Web::Api::Errors::IsArchived.new("is_archived"),
          )
        end

        context "when config.ignore_archived_errors is false" do
          before do
            allow(SlackSender.config).to receive(:ignore_archived_errors).and_return(false)
          end

          it "fails with the error" do
            expect(result).not_to be_ok
          end
        end

        context "when config.ignore_archived_errors is true" do
          before do
            allow(SlackSender.config).to receive(:ignore_archived_errors).and_return(true)
          end

          it "succeeds with done message" do
            expect(result).to be_ok
            expect(result.message).to eq("Failed successfully: ignoring 'is archived' error per config")
          end
        end
      end
    end

    describe "error handling" do
      before do
        allow(SlackSender.config).to receive(:in_production?).and_return(true)
      end

      context "when NotInChannel error occurs" do
        subject(:result) { action_class.call!(profile:, channel:, text:) }

        it "sends error notification and re-raises" do
          error_channel = profile.channels[:eng_alerts]
          call_count = 0

          allow(client_dbl).to receive(:chat_postMessage) do |args|
            call_count += 1
            raise Slack::Web::Api::Errors::NotInChannel, "not_in_channel" if call_count == 1

            expect(args[:channel]).to eq(error_channel)
            expect(args[:text]).to include("Not In Channel")
            { "ts" => "123" }
          end

          expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
        end
      end

      context "when ChannelNotFound error occurs" do
        subject(:result) { action_class.call!(profile:, channel:, text:) }

        it "sends error notification and re-raises" do
          call_count = 0
          allow(client_dbl).to receive(:chat_postMessage) do |_args|
            call_count += 1
            raise Slack::Web::Api::Errors::ChannelNotFound, "channel_not_found" if call_count == 1

            { "ts" => "123" }
          end

          expect { result }.to raise_error(Slack::Web::Api::Errors::ChannelNotFound)
        end
      end

      context "when error_channel is same as target channel" do
        subject(:result) { action_class.call!(profile:, channel: profile.channels[:eng_alerts], text:) }

        it "does not attempt recursive error notification" do
          allow(client_dbl).to receive(:chat_postMessage).and_raise(
            Slack::Web::Api::Errors::NotInChannel.new("not_in_channel"),
          )

          # Should only be called once (the original message, not error notification)
          expect(client_dbl).to receive(:chat_postMessage).once

          expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
        end
      end

      context "when error_channel is nil" do
        let(:profile_without_error_channel) do
          SlackSender::Profile.new(
            token: "SLACK_API_TOKEN",
            dev_channel: "C01H3KU3B9P",
            error_channel: nil,
            channels: { slack_development: "C01H3KU3B9P" },
            user_groups: {},
          )
        end
        subject(:result) { action_class.call!(profile: profile_without_error_channel, channel:, text:) }

        before do
          allow(client_dbl).to receive(:chat_postMessage).and_raise(
            Slack::Web::Api::Errors::NotInChannel.new("not_in_channel"),
          )
        end

        it "logs warning instead of sending slack notification" do
          expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED/)

          expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
        end
      end

      context "when error notification itself fails" do
        subject(:result) { action_class.call!(profile:, channel:, text:) }

        before do
          call_count = 0
          allow(client_dbl).to receive(:chat_postMessage) do
            call_count += 1
            raise Slack::Web::Api::Errors::NotInChannel, "not_in_channel" if call_count == 1

            raise StandardError, "error channel also failed"
          end
        end

        context "with error_notifier configured" do
          let(:notifier) { double("notifier", call: nil) }

          before do
            allow(SlackSender.config).to receive(:error_notifier).and_return(notifier)
          end

          it "calls the error_notifier with exception and context" do
            expect(notifier).to receive(:call) do |exception, context:|
              expect(exception).to be_a(StandardError)
              expect(context).to have_key(:original_error_message)
            end

            expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
          end
        end

        context "with Honeybadger available (no error_notifier)" do
          let(:honeybadger_mock) { double("Honeybadger", notify: nil) }

          before do
            allow(SlackSender.config).to receive(:error_notifier).and_return(nil)
            stub_const("Honeybadger", honeybadger_mock)
          end

          it "notifies Honeybadger with exception and context" do
            expect(honeybadger_mock).to receive(:notify) do |exception, options|
              expect(exception).to be_a(StandardError)
              expect(options[:context]).to have_key(:original_error_message)
            end

            expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
          end
        end

        context "without error_notifier or Honeybadger" do
          before do
            allow(SlackSender.config).to receive(:error_notifier).and_return(nil)
            hide_const("Honeybadger") if defined?(Honeybadger)
          end

          it "logs warning as last resort" do
            expect(action_class).to receive(:warn).with(/SLACK MESSAGE SEND FAILED.*WHILE REPORTING ERROR/m)

            expect { result }.to raise_error(Slack::Web::Api::Errors::NotInChannel)
          end
        end
      end

      context "when IsArchived error occurs" do
        subject(:result) { action_class.call(profile:, channel:, text:) }

        before do
          allow(client_dbl).to receive(:chat_postMessage).and_raise(
            Slack::Web::Api::Errors::IsArchived.new("is_archived"),
          )
        end

        context "when config.ignore_archived_errors is false" do
          before do
            allow(SlackSender.config).to receive(:ignore_archived_errors).and_return(false)
          end

          it "fails with the error" do
            expect(result).not_to be_ok
          end
        end

        context "when config.ignore_archived_errors is true" do
          before do
            allow(SlackSender.config).to receive(:ignore_archived_errors).and_return(true)
          end

          it "succeeds with done message" do
            expect(result).to be_ok
            expect(result.message).to eq("Failed successfully: ignoring 'is archived' error per config")
          end
        end

        context "when config.ignore_archived_errors is nil" do
          before do
            allow(SlackSender.config).to receive(:ignore_archived_errors).and_return(nil)
          end

          it "fails with the error" do
            expect(result).not_to be_ok
          end
        end
      end
    end
  end

  describe "text_to_use" do
    subject(:result) { action_class.call(profile:, channel:, text: "Line 1\nLine 2\nLine 3") }

    before do
      allow(SlackSender.config).to receive(:in_production?).and_return(false)
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

    context "with custom dev_channel_redirect_prefix" do
      let(:profile) do
        SlackSender::Profile.new(
          token: "SLACK_API_TOKEN",
          dev_channel: "C01H3KU3B9P",
          error_channel: "C03F1DMJ4PM",
          channels: {
            slack_development: "C01H3KU3B9P",
            eng_alerts: "C03F1DMJ4PM",
          },
          user_groups: {
            slack_development: "SLACK_DEV_TEST_USER_GROUP_HANDLE",
          },
          dev_channel_redirect_prefix: "Test prefix with %s replacement",
        )
      end

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
end
