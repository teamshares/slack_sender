# frozen_string_literal: true

RSpec.describe SlackSender::Strategy do
  let(:profile) { build(:profile) }
  let(:client_dbl) { instance_double(Slack::Web::Client) }

  before do
    allow(Slack::Web::Client).to receive(:new).and_return(client_dbl)
    allow(client_dbl).to receive(:chat_postMessage).and_return({ "ts" => "1234567890.123456" })
    allow(SlackSender.config).to receive(:in_production?).and_return(true)
    allow(SlackSender.config).to receive(:sandbox_mode?).and_return(false)

    # Register test profile
    SlackSender::ProfileRegistry.register(:test_profile, {
                                            token: "test-token",
                                            channels: { slack_development: "C01H3KU3B9P", eng_alerts: "C03F1DMJ4PM" },
                                            sandbox: { channel: { replace_with: "C01H3KU3B9P" } },
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
    describe "#slack (async)" do
      context "when async backend is available" do
        before do
          allow(SlackSender.config).to receive(:async_backend_available?).and_return(true)
          allow(SlackSender::DeliveryAxn).to receive(:call_async)
        end

        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            expects :message, type: String

            def call
              slack message
            end
          end
        end

        it "enqueues message via call_async" do
          # Channel is passed as string (channel name), validation happens in DeliveryAxn
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            hash_including(profile: "test_profile", channel: "slack_development", text: "Hello world", validate_known_channel: true),
          )

          action_class.call(message: "Hello world")
        end

        it "returns success" do
          result = action_class.call(message: "Hello world")
          # The Axn result should indicate success
          expect(result.ok?).to be true
        end

        describe "with channel override" do
          let(:action_class) do
            build_axn do
              use :slack, channel: :slack_development, profile: :test_profile

              expects :message, type: String

              def call
                slack message, channel: :eng_alerts
              end
            end
          end

          it "enqueues to overridden channel" do
            # Channel is passed as string name for async, resolved in DeliveryAxn
            expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
              hash_including(channel: "eng_alerts", validate_known_channel: true),
            )

            action_class.call(message: "Hello world")
          end
        end
      end

      context "when async backend is not available" do
        before do
          allow(SlackSender.config).to receive(:async_backend_available?).and_return(false)
        end

        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            def call
              slack "Hello"
            end
          end
        end

        it "raises SlackSender::Error" do
          expect { action_class.call! }.to raise_error(SlackSender::Error, /No async backend configured/)
        end
      end

      context "with channels: (multi-channel)" do
        let(:action_class) do
          build_axn do
            use :slack, profile: :test_profile

            expects :message, type: String

            def call
              slack message, channels: %i[slack_development eng_alerts]
            end
          end
        end

        it "enqueues to all channels" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            hash_including(channel: "slack_development", text: "Hello multi"),
          ).ordered
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            hash_including(channel: "eng_alerts", text: "Hello multi"),
          ).ordered

          action_class.call(message: "Hello multi")
        end

        context "with channels: in defaults" do
          let(:action_class) do
            build_axn do
              use :slack, channels: %i[slack_development eng_alerts], profile: :test_profile

              def call
                slack "Default multi-channel"
              end
            end
          end

          it "uses default channels" do
            expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
              hash_including(channel: "slack_development"),
            ).ordered
            expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
              hash_including(channel: "eng_alerts"),
            ).ordered

            action_class.call
          end
        end

        context "without any channel(s)" do
          let(:action_class) do
            build_axn do
              use :slack, profile: :test_profile

              def call
                slack "No channel!"
              end
            end
          end

          it "raises ArgumentError when no channel(s) provided" do
            expect { action_class.call! }.to raise_error(ArgumentError, /No channel\(s\) specified/)
          end
        end
      end
    end

    describe "#slack! (sync)" do
      let(:action_class) do
        build_axn do
          use :slack, channel: :slack_development, profile: :test_profile

          expects :message, type: String

          def call
            slack! message
          end
        end
      end

      it "sends message synchronously to default channel" do
        expect(client_dbl).to receive(:chat_postMessage).with(
          hash_including(channel: "C01H3KU3B9P", text: "Hello world"),
        )

        action_class.call(message: "Hello world")
      end

      describe "with channel override" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            expects :message, type: String

            def call
              slack! message, channel: :eng_alerts
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

      describe "with explicit kwargs" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            expects :message, type: String

            def call
              slack! text: message, icon_emoji: "robot"
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

      describe "without default channel" do
        let(:action_class) do
          build_axn do
            use :slack, profile: :test_profile

            def call
              slack! "No channel!"
            end
          end
        end

        it "raises ArgumentError when no channel provided" do
          expect { action_class.call! }.to raise_error(ArgumentError, /No channel\(s\) specified/)
        end
      end

      describe "in on_success hook" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            on_success { slack! "Success!" }

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

      describe "in on_failure hook" do
        let(:action_class) do
          build_axn do
            use :slack, channel: :slack_development, profile: :test_profile

            on_failure { slack! "Failed!", channel: :eng_alerts }

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
                                                  channels: { other_channel: "C_OTHER" },
                                                  sandbox: { channel: { replace_with: "C_OTHER" } },
                                                })
        end

        let(:action_class) do
          build_axn do
            use :slack, channel: :other_channel, profile: :other_profile

            def call
              slack! "Using other profile"
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
                                                  channels: { channel_a: "C_A" },
                                                  sandbox: { channel: { replace_with: "C_DEV_A" } },
                                                })
          SlackSender::ProfileRegistry.register(:profile_b, {
                                                  token: "token-b",
                                                  channels: { channel_b: "C_B" },
                                                  sandbox: { channel: { replace_with: "C_DEV_B" } },
                                                })
        end

        let(:action_class) do
          build_axn do
            use :slack, channel: :channel_a, profile: :profile_a

            def call
              # Override both profile and channel - channel should validate against profile_b
              slack! "message", profile: :profile_b, channel: :channel_b
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
                slack! "message", profile: :profile_b
              end
            end
          end

          it "validates default channel against the overridden profile" do
            # :channel_a is not valid in :profile_b, so this should fail. The channel is validated
            # inside the :channel preprocess lambda, so call! re-raises axn's PreprocessingError
            # (wrapping the InvalidArgumentsError) rather than a bare Axn::Failure.
            expect { action_class.call! }.to raise_error(Axn::ContractViolation::PreprocessingError, /Unknown channel/)
          end
        end

        context "when using defaults without override" do
          let(:action_class) do
            build_axn do
              use :slack, channel: :channel_a, profile: :profile_a

              def call
                slack! "message"
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
  end

  describe "strategy registration" do
    it "is registered as :slack strategy" do
      expect(Axn::Strategies.find(:slack)).to eq(SlackSender::Strategy)
    end
  end
end
