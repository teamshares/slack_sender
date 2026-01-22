# frozen_string_literal: true

RSpec.describe SlackSender::Profile do
  let(:profile) { build(:profile) }

  describe "token handling" do
    context "when token is a string" do
      it "configures client with the token value" do
        expect(profile.client.token).to eq("SLACK_API_TOKEN")
      end
    end

    context "when token is a callable" do
      let(:profile) { build(:profile, token: -> { ENV.fetch("SLACK_API_TOKEN") }) }

      it "calls the callable and configures client with the result" do
        allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_return("xoxb-lazy-token")
        expect(profile.client.token).to eq("xoxb-lazy-token")
      end

      it "memoizes the result and only evaluates the callable once" do
        call_count = 0
        token_proc = lambda {
          call_count += 1
          "token-#{call_count}"
        }
        profile_with_proc = build(:profile, token: token_proc)

        expect(profile_with_proc.client.token).to eq("token-1")
        expect(profile_with_proc.client.token).to eq("token-1")
        expect(call_count).to eq(1)
      end

      it "raises error if callable raises error (e.g., missing ENV var)" do
        allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_raise(KeyError.new("key not found: \"SLACK_API_TOKEN\""))
        expect { profile.client }.to raise_error(KeyError, /SLACK_API_TOKEN/)
      end
    end
  end

  describe "#dev_channel" do
    context "when dev_channel is provided" do
      it "returns the dev_channel value" do
        expect(profile.dev_channel).to eq("C01H3KU3B9P")
      end
    end

    context "when dev_channel is nil" do
      let(:profile) { build(:profile, dev_channel: nil) }

      it "returns nil" do
        expect(profile.dev_channel).to be_nil
      end
    end
  end

  describe "#dev_user_group" do
    context "when dev_user_group is provided" do
      let(:profile) { build(:profile, dev_user_group: "S_DEV_GROUP") }

      it "returns the dev_user_group value" do
        expect(profile.dev_user_group).to eq("S_DEV_GROUP")
      end
    end

    context "when dev_user_group is nil" do
      it "returns nil" do
        expect(profile.dev_user_group).to be_nil
      end
    end
  end

  describe "#dev_channel_redirect_prefix" do
    context "when dev_channel_redirect_prefix is provided" do
      let(:profile) { build(:profile, dev_channel_redirect_prefix: "Custom prefix: %s") }

      it "returns the dev_channel_redirect_prefix value" do
        expect(profile.dev_channel_redirect_prefix).to eq("Custom prefix: %s")
      end
    end

    context "when dev_channel_redirect_prefix is nil" do
      it "returns nil" do
        expect(profile.dev_channel_redirect_prefix).to be_nil
      end
    end
  end

  describe "#call" do
    before do
      # Register the profile in the registry
      SlackSender::ProfileRegistry.all[profile.key] = profile
      allow(SlackSender.config).to receive(:async_backend_available?).and_return(true)
    end

    context "when config.enabled is true" do
      before do
        allow(SlackSender.config).to receive(:enabled).and_return(true)
      end

      it "calls DeliveryAxn.call_async with profile name" do
        expect(SlackSender::DeliveryAxn).to receive(:call_async).with(profile: "test_profile", channel: "C123", text: "test")
        profile.call(channel: "C123", text: "test")
      end

      it "returns true" do
        allow(SlackSender::DeliveryAxn).to receive(:call_async)
        expect(profile.call(channel: "C123", text: "test")).to be true
      end

      context "with symbol channel" do
        it "preprocesses symbol channel to string and sets validate_known_channel" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            profile: "test_profile",
            channel: "slack_development",
            validate_known_channel: true,
            text: "test",
          )
          profile.call(channel: :slack_development, text: "test")
        end
      end

      context "with string channel" do
        it "does not set validate_known_channel" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            profile: "test_profile",
            channel: "C123",
            text: "test",
          )
          profile.call(channel: "C123", text: "test")
        end
      end

      context "with blocks containing symbol keys" do
        let(:blocks_with_symbols) do
          [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: ":incoming_envelope: *A block!* :tada:",
              },
            },
            {
              type: "divider",
            },
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "Has some text.",
              },
            },
          ]
        end

        it "converts symbol keys to string keys for JSON serialization" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async) do |kwargs|
            expect(kwargs[:blocks]).to be_an(Array)
            expect(kwargs[:blocks].length).to eq(3)

            # First block
            first_block = kwargs[:blocks][0]
            expect(first_block).to be_a(Hash)
            expect(first_block.keys).to all(be_a(String))
            expect(first_block["type"]).to eq("section")
            expect(first_block["text"]).to be_a(Hash)
            expect(first_block["text"]["type"]).to eq("mrkdwn")
            expect(first_block["text"]["text"]).to eq(":incoming_envelope: *A block!* :tada:")

            # Second block
            second_block = kwargs[:blocks][1]
            expect(second_block["type"]).to eq("divider")

            # Third block
            third_block = kwargs[:blocks][2]
            expect(third_block["type"]).to eq("section")
            expect(third_block["text"]["type"]).to eq("mrkdwn")
            expect(third_block["text"]["text"]).to eq("Has some text.")
          end

          profile.call(channel: "C123", blocks: blocks_with_symbols)
        end
      end

      context "with attachments containing symbol keys" do
        let(:attachments_with_symbols) do
          [
            {
              color: "good",
              title: "Success",
              text: "Everything worked!",
              fields: [
                {
                  title: "Field 1",
                  value: "Value 1",
                  short: true,
                },
              ],
            },
          ]
        end

        it "converts symbol keys to string keys for JSON serialization" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async) do |kwargs|
            expect(kwargs[:attachments]).to be_an(Array)
            expect(kwargs[:attachments].length).to eq(1)

            attachment = kwargs[:attachments][0]
            expect(attachment).to be_a(Hash)
            expect(attachment.keys).to all(be_a(String))
            expect(attachment["color"]).to eq("good")
            expect(attachment["title"]).to eq("Success")
            expect(attachment["text"]).to eq("Everything worked!")
            expect(attachment["fields"]).to be_an(Array)
            expect(attachment["fields"][0]["title"]).to eq("Field 1")
            expect(attachment["fields"][0]["value"]).to eq("Value 1")
            expect(attachment["fields"][0]["short"]).to be true
          end

          profile.call(channel: "C123", attachments: attachments_with_symbols)
        end
      end

      context "with blocks already using string keys" do
        let(:blocks_with_strings) do
          [
            {
              "type" => "section",
              "text" => {
                "type" => "mrkdwn",
                "text" => "Already strings",
              },
            },
          ]
        end

        it "leaves string keys unchanged" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async) do |kwargs|
            expect(kwargs[:blocks][0]["type"]).to eq("section")
            expect(kwargs[:blocks][0]["text"]["text"]).to eq("Already strings")
          end

          profile.call(channel: "C123", blocks: blocks_with_strings)
        end
      end

      context "with mixed symbol and string keys in blocks" do
        let(:blocks_mixed) do
          [
            {
              type: "section",
              "text" => {
                type: "mrkdwn",
                "text" => "Mixed keys",
              },
            },
          ]
        end

        it "converts all symbol keys to strings while preserving string keys" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async) do |kwargs|
            block = kwargs[:blocks][0]
            expect(block.keys).to all(be_a(String))
            expect(block["type"]).to eq("section")
            expect(block["text"]["type"]).to eq("mrkdwn")
            expect(block["text"]["text"]).to eq("Mixed keys")
          end

          profile.call(channel: "C123", blocks: blocks_mixed)
        end
      end

      context "with nil blocks" do
        it "does not raise error" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            profile: "test_profile",
            channel: "C123",
            text: "test",
          )
          profile.call(channel: "C123", text: "test", blocks: nil)
        end
      end

      context "with empty blocks array" do
        it "does not raise error" do
          expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
            profile: "test_profile",
            channel: "C123",
            text: "test",
          )
          profile.call(channel: "C123", text: "test", blocks: [])
        end
      end

      context "when profile is not registered" do
        before do
          SlackSender::ProfileRegistry.all.delete(profile.key)
        end

        it "raises an error" do
          expect { profile.call(channel: "C123", text: "test") }.to raise_error(
            SlackSender::Error,
            "Profile must be registered before using async delivery. Register it with SlackSender.register(name, config)",
          )
        end
      end

      context "when async backend is not available" do
        before do
          allow(SlackSender.config).to receive(:async_backend_available?).and_return(false)
        end

        it "raises an error about missing async backend" do
          expect { profile.call(channel: "C123", text: "test") }.to raise_error(
            SlackSender::Error,
            /No async backend configured/,
          )
        end
      end

      context "with profile parameter" do
        let(:default_profile_attrs) { { token: "DEFAULT_TOKEN", dev_channel: "C_DEFAULT" } }
        let(:other_profile_attrs) { { token: "OTHER_TOKEN", dev_channel: "C_OTHER" } }
        let(:default_profile) { SlackSender.register(**default_profile_attrs) }
        let(:other_profile) { SlackSender.register(:other_profile, **other_profile_attrs) }

        before do
          SlackSender::ProfileRegistry.clear!
          default_profile
          other_profile
        end

        context "when called on default profile" do
          # default_profile is already registered via SlackSender.register

          it "allows profile parameter to override default profile" do
            expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
              profile: "other_profile",
              channel: "C123",
              text: "test",
            )
            default_profile.call(profile: :other_profile, channel: "C123", text: "test")
          end

          it "allows profile parameter as string" do
            expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
              profile: "other_profile",
              channel: "C123",
              text: "test",
            )
            default_profile.call(profile: "other_profile", channel: "C123", text: "test")
          end
        end

        context "when called on non-default profile" do
          before do
            # Register the profile in the registry
            SlackSender::ProfileRegistry.all[profile.key] = profile
          end

          context "with matching profile parameter" do
            it "strips out redundant profile parameter" do
              expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
                profile: "test_profile",
                channel: "C123",
                text: "test",
              )
              profile.call(profile: :test_profile, channel: "C123", text: "test")
            end

            it "strips out redundant profile parameter when passed as string" do
              expect(SlackSender::DeliveryAxn).to receive(:call_async).with(
                profile: "test_profile",
                channel: "C123",
                text: "test",
              )
              profile.call(profile: "test_profile", channel: "C123", text: "test")
            end
          end

          context "with non-matching profile parameter" do
            it "raises an error" do
              expect do
                profile.call(profile: :other_profile, channel: "C123", text: "test")
              end.to raise_error(
                ArgumentError,
                /Cannot specify profile: :other_profile when calling on profile :test_profile/,
              )
            end

            it "raises an error with helpful message suggesting correct usage" do
              expect do
                profile.call(profile: :other_profile, channel: "C123", text: "test")
              end.to raise_error(
                ArgumentError,
                /Use SlackSender.profile\(:other_profile\)\.call\(\.\.\.\) instead/,
              )
            end
          end
        end

        context "when called on unregistered profile" do
          let(:unregistered_profile_attrs) { { key: :unregistered_profile, token: "UNREG_TOKEN" } }
          let(:unregistered_profile) { build(:profile, **unregistered_profile_attrs) }

          it "raises an error when profile parameter is specified" do
            expect do
              unregistered_profile.call(profile: :other_profile, channel: "C123", text: "test")
            end.to raise_error(
              ArgumentError,
              /Cannot specify profile: :other_profile when calling on unregistered profile/,
            )
          end
        end
      end
    end

    context "when config.enabled is false" do
      before do
        allow(SlackSender.config).to receive(:enabled).and_return(false)
      end

      it "does not call DeliveryAxn.call_async" do
        expect(SlackSender::DeliveryAxn).not_to receive(:call_async)
        profile.call(channel: "C123", text: "test")
      end

      it "returns false" do
        expect(profile.call(channel: "C123", text: "test")).to be false
      end
    end
  end

  describe "#call!" do
    let(:result) { instance_double("Result", thread_ts: "123.456") }

    context "when config.enabled is true" do
      before do
        allow(SlackSender.config).to receive(:enabled).and_return(true)
      end

      it "calls DeliveryAxn.call! with profile" do
        expect(SlackSender::DeliveryAxn).to receive(:call!).with(profile:, channel: "C123", text: "test").and_return(result)
        expect(profile.call!(channel: "C123", text: "test")).to eq("123.456")
      end

      context "with symbol channel" do
        it "preprocesses symbol channel to string and sets validate_known_channel" do
          expect(SlackSender::DeliveryAxn).to receive(:call!).with(
            profile:,
            channel: "slack_development",
            validate_known_channel: true,
            text: "test",
          ).and_return(result)
          expect(profile.call!(channel: :slack_development, text: "test")).to eq("123.456")
        end
      end

      context "with string channel" do
        it "does not set validate_known_channel" do
          expect(SlackSender::DeliveryAxn).to receive(:call!).with(
            profile:,
            channel: "C123",
            text: "test",
          ).and_return(result)
          expect(profile.call!(channel: "C123", text: "test")).to eq("123.456")
        end
      end

      context "with blocks containing symbol keys" do
        let(:blocks_with_symbols) do
          [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "Test block",
              },
            },
          ]
        end

        it "converts symbol keys to string keys" do
          expect(SlackSender::DeliveryAxn).to receive(:call!) do |kwargs|
            expect(kwargs[:blocks]).to be_an(Array)
            block = kwargs[:blocks][0]
            expect(block.keys).to all(be_a(String))
            expect(block["type"]).to eq("section")
            expect(block["text"]["type"]).to eq("mrkdwn")
            expect(block["text"]["text"]).to eq("Test block")
          end.and_return(result)

          profile.call!(channel: "C123", blocks: blocks_with_symbols)
        end
      end

      context "with attachments containing symbol keys" do
        let(:attachments_with_symbols) do
          [
            {
              color: "warning",
              title: "Warning",
              text: "Something happened",
            },
          ]
        end

        it "converts symbol keys to string keys" do
          expect(SlackSender::DeliveryAxn).to receive(:call!) do |kwargs|
            expect(kwargs[:attachments]).to be_an(Array)
            attachment = kwargs[:attachments][0]
            expect(attachment.keys).to all(be_a(String))
            expect(attachment["color"]).to eq("warning")
            expect(attachment["title"]).to eq("Warning")
            expect(attachment["text"]).to eq("Something happened")
          end.and_return(result)

          profile.call!(channel: "C123", attachments: attachments_with_symbols)
        end
      end

      context "with profile parameter" do
        let(:default_profile_attrs) { { token: "DEFAULT_TOKEN", dev_channel: "C_DEFAULT" } }
        let(:other_profile_attrs) { { token: "OTHER_TOKEN", dev_channel: "C_OTHER" } }
        let(:default_profile) { SlackSender.register(**default_profile_attrs) }
        let(:other_profile) { SlackSender.register(:other_profile, **other_profile_attrs) }

        before do
          SlackSender::ProfileRegistry.clear!
          default_profile
          other_profile
        end

        context "when called on default profile" do
          # default_profile is already registered via SlackSender.register

          it "allows profile parameter to override default profile" do
            # The profile parameter is converted to string and passed to DeliveryAxn,
            # which will convert it to a Profile object via its preprocess
            expect(SlackSender::DeliveryAxn).to receive(:call!).with(
              profile: "other_profile",
              channel: "C123",
              text: "test",
            ).and_return(result)
            default_profile.call!(profile: :other_profile, channel: "C123", text: "test")
          end
        end

        context "when called on non-default profile" do
          before do
            # Register the profile in the registry
            SlackSender::ProfileRegistry.all[profile.key] = profile
          end

          context "with matching profile parameter" do
            it "strips out redundant profile parameter" do
              expect(SlackSender::DeliveryAxn).to receive(:call!).with(
                profile:,
                channel: "C123",
                text: "test",
              ).and_return(result)
              profile.call!(profile: :test_profile, channel: "C123", text: "test")
            end
          end

          context "with non-matching profile parameter" do
            it "raises an error" do
              expect do
                profile.call!(profile: :other_profile, channel: "C123", text: "test")
              end.to raise_error(
                ArgumentError,
                /Cannot specify profile: :other_profile when calling on profile :test_profile/,
              )
            end
          end
        end

        context "when called on unregistered profile" do
          let(:unregistered_profile_attrs) { { key: :unregistered_profile, token: "UNREG_TOKEN" } }
          let(:unregistered_profile) { build(:profile, **unregistered_profile_attrs) }

          it "raises an error when profile parameter is specified" do
            expect do
              unregistered_profile.call!(profile: :other_profile, channel: "C123", text: "test")
            end.to raise_error(
              ArgumentError,
              /Cannot specify profile: :other_profile when calling on unregistered profile/,
            )
          end
        end
      end
    end

    context "when config.enabled is false" do
      before do
        allow(SlackSender.config).to receive(:enabled).and_return(false)
      end

      it "does not call DeliveryAxn.call!" do
        expect(SlackSender::DeliveryAxn).not_to receive(:call!)
        profile.call!(channel: "C123", text: "test")
      end

      it "returns false" do
        expect(profile.call!(channel: "C123", text: "test")).to be false
      end
    end
  end

  describe "#client" do
    it "returns a Slack::Web::Client instance" do
      expect(profile.client).to be_a(Slack::Web::Client)
    end

    it "memoizes the client instance" do
      expect(profile.client).to be(profile.client)
    end

    context "with slack_client_config" do
      let(:profile) { build(:profile, slack_client_config: { timeout: 30, open_timeout: 10 }) }

      it "merges slack_client_config into client" do
        expect(profile.client.timeout).to eq(30)
        expect(profile.client.open_timeout).to eq(10)
      end
    end
  end

  describe "#format_group_mention" do
    before do
      allow(SlackSender.config).to receive(:in_production?).and_return(production?)
    end

    context "in production" do
      let(:production?) { true }

      context "with symbol key" do
        let(:profile) { build(:profile, user_groups: { eng_team: "S123ABC" }) }

        it "returns formatted group link for user group symbol" do
          result = profile.format_group_mention(:eng_team)

          expect(result).to eq("<!subteam^S123ABC>")
        end
      end

      context "with string ID" do
        it "returns formatted group link for string ID" do
          result = profile.format_group_mention("S123ABC")

          expect(result).to eq("<!subteam^S123ABC>")
        end
      end

      context "with dev_user_group configured" do
        let(:profile) { build(:profile, dev_user_group: "S_DEV_GROUP", user_groups: { eng_team: "S123ABC" }) }

        it "ignores dev_user_group and returns requested group link" do
          result = profile.format_group_mention(:eng_team)

          expect(result).to eq("<!subteam^S123ABC>")
        end
      end

      context "with unknown symbol key" do
        it "raises error" do
          expect { profile.format_group_mention(:unknown_group) }.to raise_error("Unknown user group: unknown_group")
        end
      end
    end

    context "not in production" do
      let(:production?) { false }

      context "with dev_user_group configured" do
        let(:profile) { build(:profile, dev_user_group: "S_DEV_GROUP", user_groups: { eng_team: "S123ABC" }) }

        context "with symbol key" do
          it "returns dev_user_group link instead of requested group" do
            result = profile.format_group_mention(:eng_team)

            expect(result).to eq("<!subteam^S_DEV_GROUP>")
          end
        end

        context "with string ID" do
          it "returns dev_user_group link instead of requested ID" do
            result = profile.format_group_mention("S123ABC")

            expect(result).to eq("<!subteam^S_DEV_GROUP>")
          end
        end
      end

      context "when dev_user_group is not configured" do
        let(:profile) { build(:profile, dev_user_group: nil, user_groups: { eng_team: "S123ABC" }) }

        it "returns the requested group link" do
          result = profile.format_group_mention(:eng_team)

          expect(result).to eq("<!subteam^S123ABC>")
        end
      end

      context "when dev_user_group is empty string" do
        let(:profile) { build(:profile, dev_user_group: "", user_groups: { eng_team: "S123ABC" }) }

        it "returns the requested group link (empty string is not present)" do
          result = profile.format_group_mention(:eng_team)

          expect(result).to eq("<!subteam^S123ABC>")
        end
      end
    end
  end
end
