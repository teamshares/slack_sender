# frozen_string_literal: true

RSpec.describe SlackSender::Strategy do
  let(:profile) { build(:profile) }
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "1234567890.123456" })
    allow(SlackSender.config).to receive(:in_production?).and_return(true)

    # Register test profile
    SlackSender::ProfileRegistry.register(:test_profile, {
                                            token: "test-token",
                                            dev_channel: "C01H3KU3B9P",
                                            error_channel: "C03F1DMJ4PM",
                                            channels: { slack_development: "C01H3KU3B9P", eng_alerts: "C03F1DMJ4PM" },
                                          })
  end

  after do
    SlackSender::ProfileRegistry.clear!
  end

  describe ".configure" do
    it "returns a module" do
      result = described_class.configure(channel: :slack_development)
      expect(result).to be_a(Module)
    end
  end

  describe "strategy usage in an Axn" do
    let(:action_class) do
      build_axn do
        use :slack, channel: :slack_development, profile: :test_profile

        expects :message, type: String

        def call
          slack message
        end
      end
    end

    describe "slack method with positional text argument" do
      it "sends message to default channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C01H3KU3B9P", text: "Hello world"),
        )

        action_class.call(message: "Hello world")
      end
    end

    describe "slack method with channel override" do
      let(:action_class) do
        build_axn do
          use :slack, channel: :slack_development, profile: :test_profile

          expects :message, type: String

          def call
            slack message, channel: :eng_alerts
          end
        end
      end

      it "sends to overridden channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C03F1DMJ4PM", text: "Hello world"),
        )

        action_class.call(message: "Hello world")
      end
    end

    describe "slack method with explicit kwargs" do
      let(:action_class) do
        build_axn do
          use :slack, channel: :slack_development, profile: :test_profile

          expects :message, type: String

          def call
            slack text: message, icon_emoji: "robot"
          end
        end
      end

      it "passes kwargs to SlackSender" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(text: "Hello world", icon_emoji: ":robot:"),
        )

        action_class.call(message: "Hello world")
      end
    end

    describe "slack method without default channel" do
      let(:action_class) do
        build_axn do
          use :slack, profile: :test_profile

          def call
            slack "No channel!"
          end
        end
      end

      it "raises ArgumentError when no channel provided" do
        expect { action_class.call! }.to raise_error(ArgumentError, /No channel specified/)
      end
    end

    describe "slack method in on_success hook" do
      let(:action_class) do
        build_axn do
          use :slack, channel: :slack_development, profile: :test_profile

          on_success { slack "Success!" }

          def call
            # Do nothing, just succeed
          end
        end
      end

      it "sends message on success" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(text: "Success!"),
        )

        action_class.call
      end
    end

    describe "slack method in on_failure hook" do
      let(:action_class) do
        build_axn do
          use :slack, channel: :slack_development, profile: :test_profile

          on_failure { slack "Failed!", channel: :eng_alerts }

          def call
            fail! "Something went wrong"
          end
        end
      end

      it "sends message on failure" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C03F1DMJ4PM", text: "Failed!"),
        )

        action_class.call
      end
    end

    describe "with different profile" do
      before do
        SlackSender::ProfileRegistry.register(:other_profile, {
                                                token: "other-token",
                                                dev_channel: "C_OTHER",
                                                channels: { other_channel: "C_OTHER" },
                                              })
      end

      let(:action_class) do
        build_axn do
          use :slack, channel: :other_channel, profile: :other_profile

          def call
            slack "Using other profile"
          end
        end
      end

      it "uses the specified profile" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C_OTHER"),
        )

        action_class.call
      end
    end

    describe "overriding profile at call time" do
      before do
        SlackSender::ProfileRegistry.register(:profile_a, {
                                                token: "token-a",
                                                dev_channel: "C_DEV_A",
                                                channels: { channel_a: "C_A" },
                                              })
        SlackSender::ProfileRegistry.register(:profile_b, {
                                                token: "token-b",
                                                dev_channel: "C_DEV_B",
                                                channels: { channel_b: "C_B" },
                                              })
      end

      let(:action_class) do
        build_axn do
          use :slack, channel: :channel_a, profile: :profile_a

          def call
            # Override both profile and channel - channel should validate against profile_b
            slack "message", profile: :profile_b, channel: :channel_b
          end
        end
      end

      it "validates channel against the overridden profile" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C_B"),
        )

        action_class.call
      end

      context "when overriding only the profile but using default channel" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :channel_a, profile: :profile_a

            def call
              # Override profile, use default channel - channel should validate against profile_b
              slack "message", profile: :profile_b
            end
          end
        end

        it "validates default channel against the overridden profile" do
          # :channel_a is not valid in :profile_b, so this should fail
          expect { action_class.call! }.to raise_error(Axn::Failure, /Unknown channel/)
        end
      end

      context "when using defaults without override" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :channel_a, profile: :profile_a

            def call
              slack "message"
            end
          end
        end

        it "uses default profile and channel" do
          expect(client_dbl).to receive(:chat_postMessage).with(
            hash_including(channel: "C_A"),
          )

          action_class.call
        end
      end
    end
  end

  describe "strategy registration" do
    it "is registered as :slack strategy" do
      expect(Axn::Strategies.find(:slack)).to eq(SlackSender::Strategy)
    end
  end
end
