# frozen_string_literal: true

RSpec.describe Slacker::Profile do
  let(:profile) do
    described_class.new(
      token: "SLACK_API_TOKEN",
      dev_channel: "C01H3KU3B9P",
      error_channel: "C03F1DMJ4PM",
      channels: { slack_development: "C01H3KU3B9P" },
      user_groups: { slack_development: "S123" },
    )
  end

  describe "#token" do
    context "when token is a string" do
      it "returns the token value" do
        expect(profile.token).to eq("SLACK_API_TOKEN")
      end
    end

    context "when token is a callable" do
      let(:profile) do
        described_class.new(
          token: -> { ENV.fetch("SLACK_API_TOKEN") },
          dev_channel: "C01H3KU3B9P",
          error_channel: "C03F1DMJ4PM",
          channels: { slack_development: "C01H3KU3B9P" },
          user_groups: { slack_development: "S123" },
        )
      end

      it "calls the callable and returns the result" do
        allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_return("xoxb-lazy-token")
        expect(profile.token).to eq("xoxb-lazy-token")
      end

      it "memoizes the result and only evaluates the callable once" do
        call_count = 0
        token_proc = lambda {
          call_count += 1
          "token-#{call_count}"
        }
        profile_with_proc = described_class.new(
          token: token_proc,
          channels: {},
          user_groups: {},
        )

        expect(profile_with_proc.token).to eq("token-1")
        expect(profile_with_proc.token).to eq("token-1")
        expect(call_count).to eq(1)
      end

      it "raises error if callable raises error (e.g., missing ENV var)" do
        allow(ENV).to receive(:fetch).with("SLACK_API_TOKEN").and_raise(KeyError.new("key not found: \"SLACK_API_TOKEN\""))
        expect { profile.token }.to raise_error(KeyError, /SLACK_API_TOKEN/)
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
      let(:profile) do
        described_class.new(
          token: "SLACK_API_TOKEN",
          dev_channel: nil,
          channels: {},
          user_groups: {},
        )
      end

      it "returns nil" do
        expect(profile.dev_channel).to be_nil
      end
    end
  end

  describe "#dev_channel_redirect_prefix" do
    context "when dev_channel_redirect_prefix is provided" do
      let(:profile) do
        described_class.new(
          token: "SLACK_API_TOKEN",
          dev_channel_redirect_prefix: "Custom prefix: %s",
          channels: {},
          user_groups: {},
        )
      end

      it "returns the dev_channel_redirect_prefix value" do
        expect(profile.dev_channel_redirect_prefix).to eq("Custom prefix: %s")
      end
    end

    context "when dev_channel_redirect_prefix is nil" do
      let(:profile) do
        described_class.new(
          token: "SLACK_API_TOKEN",
          dev_channel_redirect_prefix: nil,
          channels: {},
          user_groups: {},
        )
      end

      it "returns nil" do
        expect(profile.dev_channel_redirect_prefix).to be_nil
      end
    end
  end

  describe "#call" do
    before do
      # Set the registered_name on the profile instance
      profile.instance_variable_set(:@registered_name, :test_profile)
      allow(Slacker.config).to receive(:async_backend_available?).and_return(true)
    end

    it "calls DeliveryAxn.call_async with profile name" do
      expect(Slacker::DeliveryAxn).to receive(:call_async).with(profile: "test_profile", channel: "C123", text: "test")
      profile.call(channel: "C123", text: "test")
    end

    it "returns true" do
      allow(Slacker::DeliveryAxn).to receive(:call_async)
      expect(profile.call(channel: "C123", text: "test")).to be true
    end

    context "when profile is not registered" do
      before do
        profile.remove_instance_variable(:@registered_name) if profile.instance_variable_defined?(:@registered_name)
      end

      it "raises an error" do
        expect { profile.call(channel: "C123", text: "test") }.to raise_error(
          Slacker::Error,
          "Profile must be registered before using async delivery. Register it with Slacker.register(name, config)",
        )
      end
    end
  end

  describe "#call!" do
    let(:result) { instance_double("Result", thread_ts: "123.456") }

    it "calls DeliveryAxn.call! with profile" do
      expect(Slacker::DeliveryAxn).to receive(:call!).with(profile:, channel: "C123", text: "test").and_return(result)
      expect(profile.call!(channel: "C123", text: "test")).to eq("123.456")
    end
  end

  describe "#format_group_mention" do
    before do
      allow(Slacker.config).to receive(:in_production?).and_return(production?)
    end

    context "in production" do
      let(:production?) { true }

      context "with symbol key" do
        let(:profile) do
          described_class.new(
            token: "SLACK_API_TOKEN",
            user_groups: { eng_team: "S123ABC" },
            channels: {},
          )
        end

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

      context "with unknown symbol key" do
        it "raises error" do
          expect { profile.format_group_mention(:unknown_group) }.to raise_error("Unknown user group: unknown_group")
        end
      end
    end

    context "not in production" do
      let(:production?) { false }

      context "with symbol key" do
        let(:profile) do
          described_class.new(
            token: "SLACK_API_TOKEN",
            user_groups: {
              eng_team: "S123ABC",
              slack_development: "S_DEV_GROUP",
            },
            channels: {},
          )
        end

        it "returns dev group link instead of requested group" do
          result = profile.format_group_mention(:eng_team)

          expect(result).to eq("<!subteam^S_DEV_GROUP>")
        end
      end

      context "with string ID" do
        it "returns dev group link instead of requested ID" do
          result = profile.format_group_mention("S123ABC")

          expect(result).to eq("<!subteam^#{profile.user_groups[:slack_development]}>")
        end
      end

      context "when slack_development user group is not configured" do
        let(:profile) do
          described_class.new(
            token: "SLACK_API_TOKEN",
            user_groups: { eng_team: "S123ABC" },
            channels: {},
          )
        end

        it "uses nil group_id and formats it as empty subteam link" do
          result = profile.format_group_mention(:eng_team)

          # When slack_development is missing, group_id becomes nil
          # Slack::Messages::Formatting.group_link(nil) returns "<!subteam^>"
          expect(result).to eq("<!subteam^>")
        end
      end
    end
  end
end
