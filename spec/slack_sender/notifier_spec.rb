# frozen_string_literal: true

RSpec.describe SlackSender::Notifier do
  let(:profile) { build(:profile) }
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "1234567890.123456" })
    allow(SlackSender.config).to receive(:in_production?).and_return(true)
    allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)
    # Enable async backend for Notifier tests (Notifier uses slack() which is async)
    allow(SlackSender.config).to receive(:async_backend_available?).and_return(true)
    # Stub call_async to actually call synchronously for test verification
    allow(SlackSender::DeliveryAxn).to receive(:call_async) do |**kwargs|
      SlackSender::DeliveryAxn.call!(**kwargs)
    end

    SlackSender::ProfileRegistry.register(:default, {
                                            token: "test-token",
                                            channels: {
                                              slack_development: "C01H3KU3B9P",
                                              eng_alerts: "C03F1DMJ4PM",
                                              notifications: "C_NOTIFICATIONS",
                                              other_channel: "C_OTHER",
                                            },
                                            sandbox: { channel: { replace_with: "C01H3KU3B9P" } },
                                          })
  end

  after do
    SlackSender::ProfileRegistry.clear!
  end

  describe "basic notify usage" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text { "Hello from notifier!" }
        end
      end
    end

    it "sends message to specified channel" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS", text: "Hello from notifier!"),
      )

      notifier_class.call
    end
  end

  describe "notify with slack_options passthrough" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text { "https://example.com/runbook" }
          slack_options unfurl_links: false, unfurl_media: false
        end
      end
    end

    it "forwards slack_options from the notify block to chat_postMessage" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "https://example.com/runbook", unfurl_links: false, unfurl_media: false),
      )

      notifier_class.call
    end
  end

  describe "notify with expects" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :user_name, type: String

        notify do
          channel :notifications
          text { "Hello, #{user_name}!" }
        end
      end
    end

    it "can use expected values in text block" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "Hello, Alice!"),
      )

      notifier_class.call(user_name: "Alice")
    end
  end

  describe "notify with static text" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text "Static message"
        end
      end
    end

    it "sends static text directly" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "Static message"),
      )

      notifier_class.call
    end
  end

  describe "notify with text as symbol method ref" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text :message_text
        end

        def message_text
          "From method!"
        end
      end
    end

    it "resolves symbol to method call" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "From method!"),
      )

      notifier_class.call
    end
  end

  describe "notify with dynamic channel" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :target_channel, type: Symbol

        notify do
          channel :target_channel
          text "Dynamic channel message"
        end

        # target_channel accessor is automatically created by expects
      end
    end

    it "resolves channel from method" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C03F1DMJ4PM"),
      )

      notifier_class.call(target_channel: :eng_alerts)
    end
  end

  describe "notify with multi-channel via channels DSL" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channels :notifications, :eng_alerts
          text "Multi-channel message"
        end
      end
    end

    it "sends to all channels" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS"),
      ).ordered

      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C03F1DMJ4PM"),
      ).ordered

      notifier_class.call
    end

    it "uses channels: kwarg for efficiency (single slack call with multiple channels)" do
      # Verify it's using the channels: kwarg path (one call to slack with channels:)
      # rather than looping and calling slack individually
      expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
        hash_including(channel: "notifications", validate_known_channel: true),
      ).ordered

      expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
        hash_including(channel: "eng_alerts", validate_known_channel: true),
      ).ordered

      notifier_class.call
    end
  end

  describe "notify with single channel" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text "Single channel message"
        end
      end
    end

    it "uses channel: kwarg (not channels:)" do
      expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
        hash_including(channel: "notifications", validate_known_channel: true),
      ).once

      notifier_class.call
    end
  end

  describe "notify with only_if condition (symbol)" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :should_send, type: :boolean

        notify do
          channel :notifications
          text "Conditional message"
          only_if :should_send?
        end

        def should_send?
          should_send
        end
      end
    end

    context "when condition is true" do
      it "sends the message" do
        expect(client_dbl).to receive(:chat_postMessage)

        notifier_class.call(should_send: true)
      end
    end

    context "when condition is false" do
      it "does not send the message" do
        expect(client_dbl).not_to receive(:chat_postMessage)

        notifier_class.call(should_send: false)
      end
    end
  end

  describe "notify with only_if condition (block)" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :count, type: Integer

        notify do
          channel :notifications
          text "Count message"
          only_if { count > 5 }
        end

        # count accessor is automatically created by expects
      end
    end

    context "when block returns true" do
      it "sends the message" do
        expect(client_dbl).to receive(:chat_postMessage)

        notifier_class.call(count: 10)
      end
    end

    context "when block returns false" do
      it "does not send the message" do
        expect(client_dbl).not_to receive(:chat_postMessage)

        notifier_class.call(count: 3)
      end
    end
  end

  describe "multiple notify declarations" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text "First message"
        end

        notify do
          channel :eng_alerts
          text "Second message"
        end
      end
    end

    it "sends all messages" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS", text: "First message"),
      ).ordered

      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C03F1DMJ4PM", text: "Second message"),
      ).ordered

      notifier_class.call
    end
  end

  describe "multiple notify with different conditions" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :priority, type: Symbol

        notify do
          channel :notifications
          text "Normal priority"
          only_if { priority == :normal }
        end

        notify do
          channel :eng_alerts
          text "High priority!"
          only_if { priority == :high }
        end
      end
    end

    context "with normal priority" do
      it "only sends to notifications channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C_NOTIFICATIONS"),
        ).once

        notifier_class.call(priority: :normal)
      end
    end

    context "with high priority" do
      it "only sends to eng_alerts channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C03F1DMJ4PM"),
        ).once

        notifier_class.call(priority: :high)
      end
    end
  end

  describe "notify with additional payload options" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text :message_text
          icon_emoji :emoji
          attachments :build_attachments
        end

        def message_text
          "Message with extras"
        end

        def emoji
          "rocket"
        end

        def build_attachments
          [{ color: "good", text: "Attachment text" }]
        end
      end
    end

    it "passes all options to slack method" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(
          text: "Message with extras",
          icon_emoji: ":rocket:",
          attachments: [{ "color" => "good", "text" => "Attachment text" }],
        ),
      )

      notifier_class.call
    end
  end

  describe "inheritance" do
    let(:base_notifier) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text "Base message"
        end
      end
    end

    let(:child_notifier) do
      Class.new(base_notifier) do
        notify do
          channel :eng_alerts
          text "Child message"
        end
      end
    end

    it "child includes parent notify declarations" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS", text: "Base message"),
      ).ordered

      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C03F1DMJ4PM", text: "Child message"),
      ).ordered

      child_notifier.call
    end

    it "parent is not affected by child" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS"),
      ).once

      base_notifier.call
    end
  end

  describe "class attributes isolation" do
    let(:notifier_a) do
      Class.new(described_class) do
        notify do
          channel :notifications
          text "Notifier A"
        end
      end
    end

    let(:notifier_b) do
      Class.new(described_class) do
        notify do
          channel :eng_alerts
          text "Notifier B"
        end
      end
    end

    it "each notifier has its own config" do
      expect(notifier_a._notification_definitions.length).to eq(1)
      expect(notifier_b._notification_definitions.length).to eq(1)

      # Verify they have different channel configs (checking via execution)
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C_NOTIFICATIONS"),
      )
      notifier_a.call

      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(channel: "C03F1DMJ4PM"),
      )
      notifier_b.call
    end
  end

  describe "notify validation" do
    it "raises ArgumentError when notify called without block" do
      expect do
        Class.new(described_class) do
          notify
        end
      end.to raise_error(ArgumentError, /notify requires a block/)
    end

    it "raises ArgumentError for missing channel at execution time" do
      notifier_class = Class.new(described_class) do
        notify do
          text "No channel"
        end
      end

      result = notifier_class.call
      expect(result).not_to be_ok
      expect(result.exception).to be_a(ArgumentError)
      expect(result.exception.message).to match(/Missing `channel`/)
    end

    it "raises ArgumentError for missing payload at execution time" do
      notifier_class = Class.new(described_class) do
        notify do
          channel :notifications
        end
      end

      result = notifier_class.call
      expect(result).not_to be_ok
      expect(result.exception).to be_a(ArgumentError)
      expect(result.exception.message).to match(/Missing payload/)
    end

    # Regression: a DeliveryAxn failure bubbling up through a Notifier is a nested call!,
    # so axn aggregates base headers (PRO-2820/#132). The Notifier declares no base, so the
    # aggregated result.error is just DeliveryAxn's prefixed message — no double prefix, no
    # "...: Something went wrong" noise. The foreign exception keeps its raw technical #message.
    context "when the underlying Slack delivery fails" do
      let(:notifier_class) do
        Class.new(described_class) do
          notify do
            channel :notifications
            text { "Hello" }
          end
        end
      end

      before do
        slack_error = Slack::Web::Api::Errors::SlackError.new("unknown_error")
        allow(slack_error).to receive(:response).and_return(nil)
        allow(slack_error).to receive(:error).and_return("unknown_error")
        allow(slack_error).to receive(:response_metadata).and_return(nil)
        allow(client_dbl).to receive(:chat_postMessage).and_raise(slack_error)
      end

      it "surfaces DeliveryAxn's base-prefixed message on result.error (no double prefix)" do
        result = notifier_class.call
        expect(result).not_to be_ok
        expect(result.error).to eq("Unable to send Slack message: unknown_error")
      end

      it "keeps the original technical message on the foreign exception" do
        result = notifier_class.call
        expect(result.exception).to be_a(Slack::Web::Api::Errors::SlackError)
        expect(result.exception.message).to eq("unknown_error")
      end
    end
  end

  describe "resolution precedence" do
    describe "block takes precedence" do
      let(:notifier_class) do
        Class.new(described_class) do
          notify do
            channel :notifications
            text { "from block" }
          end

          def text
            "from method"
          end
        end
      end

      it "uses block value" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(text: "from block"),
        )

        notifier_class.call
      end
    end

    describe "symbol resolves to method if exists" do
      let(:notifier_class) do
        Class.new(described_class) do
          notify do
            channel :notifications
            text :custom_text
          end

          def custom_text
            "resolved from custom_text method"
          end
        end
      end

      it "calls the method" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(text: "resolved from custom_text method"),
        )

        notifier_class.call
      end
    end

    describe "symbol remains literal if no matching method" do
      let(:notifier_class) do
        Class.new(described_class) do
          notify do
            channel :notifications # :notifications is not a method, stays as symbol
            text "test"
          end
        end
      end

      it "symbol channel is resolved via profile" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C_NOTIFICATIONS"),
        )

        notifier_class.call
      end
    end
  end
end
