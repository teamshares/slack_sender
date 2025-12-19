# frozen_string_literal: true

RSpec.describe SlackOutbox::DeliveryAxn do
  let(:profile) do
    SlackOutbox::Profile.new(
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
  let(:action_class) { SlackOutbox::DeliveryAxn }
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
    describe "channel preprocessing" do
      before do
        allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
      end

      context "with symbol channel key" do
        subject(:result) { action_class.call(profile:, channel: :slack_development, text:) }

        it "resolves to channel ID" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: profile.channels[:slack_development]),
          )

          expect(result).to be_ok
        end
      end

      context "with unknown symbol channel key" do
        subject(:result) { action_class.call(profile:, channel: :unknown_channel, text:) }

        it "fails with preprocessing error" do
          expect(result).not_to be_ok
          expect(result.error).to include("Unknown channel: unknown_channel")
        end
      end

      context "with string channel ID" do
        subject(:result) { action_class.call(profile:, channel: "C123456", text:) }

        it "uses the channel ID directly" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: "C123456"),
          )

          expect(result).to be_ok
        end
      end
    end

    describe "text preprocessing" do
      before do
        allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
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
        allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
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

        it "passes nil" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(icon_emoji: nil),
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
          allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
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
        allow(SlackOutbox.config).to receive(:in_production?).and_return(production?)
      end

      context "in production" do
        let(:production?) { true }

        it "posts to actual channel with actual text" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            channel:,
            text:,
            blocks: nil,
            attachments: nil,
            icon_emoji: nil,
            thread_ts: nil,
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
            channel: profile.channels[:slack_development],
            text: a_string_matching(/test.*tube.*Would have been sent to.*#{channel}.*production/m),
            blocks: nil,
            attachments: nil,
            icon_emoji: nil,
            thread_ts: nil,
          )

          expect(result).to be_ok
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
        allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
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
    end

    describe "error handling" do
      before do
        allow(SlackOutbox.config).to receive(:in_production?).and_return(true)
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
          SlackOutbox::Profile.new(
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
    end
  end

  describe ".format_group_mention" do
    before do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(production?)
    end

    context "in production" do
      let(:production?) { true }

      it "returns formatted group link for string ID" do
        result = action_class.format_group_mention(profile, "S123ABC")

        expect(result).to eq("<!subteam^S123ABC>")
      end
    end

    context "not in production" do
      let(:production?) { false }

      it "returns dev group link by default" do
        result = action_class.format_group_mention(profile, "S123ABC")

        expect(result).to eq("<!subteam^#{profile.user_groups[:slack_development]}>")
      end

      it "uses custom non_production fallback if provided" do
        result = action_class.format_group_mention(profile, "S123ABC", "S_CUSTOM_DEV")

        expect(result).to eq("<!subteam^S_CUSTOM_DEV>")
      end
    end
  end

  describe "text_to_use" do
    subject(:result) { action_class.call(profile:, channel:, text: "Line 1\nLine 2\nLine 3") }

    before do
      allow(SlackOutbox.config).to receive(:in_production?).and_return(false)
    end

    it "wraps each line with quote formatting" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(
          text: a_string_matching(/> Line 1.*> Line 2.*> Line 3/m),
        ),
      )

      expect(result).to be_ok
    end
  end
end
