# frozen_string_literal: true

RSpec.describe SlackSender::Notifier do
  let(:profile) { build(:profile) }
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "1234567890.123456" })
    allow(SlackSender.config).to receive(:in_production?).and_return(true)

    SlackSender::ProfileRegistry.register(:default, {
                                            token: "test-token",
                                            dev_channel: "C01H3KU3B9P",
                                            error_channel: "C03F1DMJ4PM",
                                            channels: {
                                              slack_development: "C01H3KU3B9P",
                                              eng_alerts: "C03F1DMJ4PM",
                                              notifications: "C_NOTIFICATIONS",
                                              other_channel: "C_OTHER",
                                            },
                                          })
  end

  after do
    SlackSender::ProfileRegistry.clear!
  end

  describe "basic notify_via usage" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify_via channel: :notifications, text: :message_text

        def message_text
          "Hello from notifier!"
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

  describe "notify_via with expects" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :user_name, type: String

        notify_via channel: :notifications, text: :greeting

        def greeting
          "Hello, #{user_name}!"
        end
      end
    end

    it "can use expected values in text method" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "Hello, Alice!"),
      )

      notifier_class.call(user_name: "Alice")
    end
  end

  describe "notify_via with static text" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify_via channel: :notifications, text: "Static message"
      end
    end

    it "sends static text directly" do
      expect(client_dbl).to receive(:chat_postMessage).with(
        hash_including(text: "Static message"),
      )

      notifier_class.call
    end
  end

  describe "notify_via with dynamic channel" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :target_channel, type: Symbol

        notify_via channel: :target_channel, text: "Dynamic channel message"

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

  describe "notify_via with multi-channel" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify_via channel: %i[notifications eng_alerts], text: "Multi-channel message"
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
  end

  describe "notify_via with if condition (symbol)" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :should_send, type: :boolean

        notify_via channel: :notifications, text: "Conditional message", if: :should_send?

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

  describe "notify_via with if condition (lambda)" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :count, type: Integer

        notify_via channel: :notifications, text: "Count message", if: -> { count > 5 }

        # count accessor is automatically created by expects
      end
    end

    context "when lambda returns true" do
      it "sends the message" do
        expect(client_dbl).to receive(:chat_postMessage)

        notifier_class.call(count: 10)
      end
    end

    context "when lambda returns false" do
      it "does not send the message" do
        expect(client_dbl).not_to receive(:chat_postMessage)

        notifier_class.call(count: 3)
      end
    end
  end

  describe "notify_via with unless condition" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :archived, type: :boolean

        notify_via channel: :notifications, text: "Not archived message", unless: :archived?

        def archived?
          archived
        end
      end
    end

    context "when condition is false" do
      it "sends the message" do
        expect(client_dbl).to receive(:chat_postMessage)

        notifier_class.call(archived: false)
      end
    end

    context "when condition is true" do
      it "does not send the message" do
        expect(client_dbl).not_to receive(:chat_postMessage)

        notifier_class.call(archived: true)
      end
    end
  end

  describe "multiple notify_via declarations" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify_via channel: :notifications, text: "First message"
        notify_via channel: :eng_alerts, text: "Second message"
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

  describe "multiple notify_via with different conditions" do
    let(:notifier_class) do
      Class.new(described_class) do
        expects :priority, type: Symbol

        notify_via channel: :notifications, text: "Normal priority", if: :normal_priority?
        notify_via channel: :eng_alerts, text: "High priority!", if: :high_priority?

        def normal_priority?
          priority == :normal
        end

        def high_priority?
          priority == :high
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

  describe "notify_via with additional kwargs" do
    let(:notifier_class) do
      Class.new(described_class) do
        notify_via channel: :notifications, text: :message_text, icon_emoji: :emoji, attachments: :build_attachments

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

    it "passes all kwargs to slack method" do
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
        notify_via channel: :notifications, text: "Base message"
      end
    end

    let(:child_notifier) do
      Class.new(base_notifier) do
        notify_via channel: :eng_alerts, text: "Child message"
      end
    end

    it "child includes parent notify_via declarations" do
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
        notify_via channel: :notifications, text: "Notifier A"
      end
    end

    let(:notifier_b) do
      Class.new(described_class) do
        notify_via channel: :eng_alerts, text: "Notifier B"
      end
    end

    it "each notifier has its own config" do
      expect(notifier_a._notify_via_configs.length).to eq(1)
      expect(notifier_b._notify_via_configs.length).to eq(1)

      expect(notifier_a._notify_via_configs.first[:channel]).to eq(:notifications)
      expect(notifier_b._notify_via_configs.first[:channel]).to eq(:eng_alerts)
    end
  end

  describe "notify_via validation" do
    it "raises ArgumentError for unknown keys" do
      expect {
        Class.new(described_class) do
          notify_via channel: :notifications, text: "Test", invalid_key: "value"
        end
      }.to raise_error(ArgumentError, /Unknown keys for notify_via: :invalid_key/)
    end

    it "raises ArgumentError with all unknown keys listed" do
      expect {
        Class.new(described_class) do
          notify_via channel: :notifications, text: "Test", invalid1: "v1", invalid2: "v2"
        end
      }.to raise_error(ArgumentError, /Unknown keys for notify_via: :invalid1, :invalid2/)
    end

    it "accepts all valid keys" do
      expect {
        Class.new(described_class) do
          notify_via(
            channel: :notifications,
            text: "Test",
            if: :condition?,
            unless: :skip?,
            profile: :default,
            blocks: [],
            attachments: [],
            icon_emoji: ":rocket:",
            thread_ts: "123.456",
            files: [],
          )
        end
      }.not_to raise_error
    end
  end
end
