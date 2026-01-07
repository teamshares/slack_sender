# frozen_string_literal: true

RSpec.describe SlackSender do
  after do
    SlackSender::ProfileRegistry.clear!
  end

  describe ".register" do
    context "when called with no positional argument (only kwargs)" do
      it "registers a named :default profile and sets it as default" do
        profile = described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )

        expect(profile).to be_a(SlackSender::Profile)
        expect(profile.dev_channel).to eq("C123")
        expect(described_class.profile(:default)).to eq(profile)
        expect(described_class.default_profile).to eq(profile)
      end

      it "raises error if :default profile already registered" do
        described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )

        expect do
          described_class.register(
            token: "OTHER_TOKEN",
            dev_channel: "C456",
            channels: {},
            user_groups: {},
          )
        end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
      end

      it "raises error if :default already registered via explicit :default call" do
        described_class.register(:default,
                                 token: "TEST_TOKEN",
                                 dev_channel: "C123",
                                 channels: {},
                                 user_groups: {})

        expect do
          described_class.register(
            token: "OTHER_TOKEN",
            dev_channel: "C456",
            channels: {},
            user_groups: {},
          )
        end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
      end
    end

    context "when called with :default as first argument" do
      it "registers a named :default profile and sets it as default" do
        profile = described_class.register(:default,
                                           token: "TEST_TOKEN",
                                           dev_channel: "C123",
                                           channels: {},
                                           user_groups: {})

        expect(profile).to be_a(SlackSender::Profile)
        expect(profile.dev_channel).to eq("C123")
        expect(described_class.profile(:default)).to eq(profile)
        expect(described_class.default_profile).to eq(profile)
      end

      it "raises error if :default profile already registered" do
        described_class.register(:default,
                                 token: "TEST_TOKEN",
                                 dev_channel: "C123",
                                 channels: {},
                                 user_groups: {})

        expect do
          described_class.register(:default,
                                   token: "OTHER_TOKEN",
                                   dev_channel: "C456",
                                   channels: {},
                                   user_groups: {})
        end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
      end

      it "raises error if :default already registered via no-arg call" do
        described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )

        expect do
          described_class.register(:default,
                                   token: "OTHER_TOKEN",
                                   dev_channel: "C456",
                                   channels: {},
                                   user_groups: {})
        end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
      end

      it "behaves identically to calling with no positional argument" do
        profile1 = described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )

        SlackSender::ProfileRegistry.clear!

        profile2 = described_class.register(:default,
                                            token: "TEST_TOKEN",
                                            dev_channel: "C123",
                                            channels: {},
                                            user_groups: {})

        expect(profile1.dev_channel).to eq(profile2.dev_channel)
        expect(profile1.token).to eq(profile2.token)
      end
    end

    context "when called with other name as first argument" do
      it "registers a named profile" do
        profile = described_class.register(:production,
                                           token: "TEST_TOKEN",
                                           dev_channel: "C123",
                                           channels: {},
                                           user_groups: {})

        expect(profile).to be_a(SlackSender::Profile)
        expect(profile.dev_channel).to eq("C123")
        expect(described_class.profile(:production)).to eq(profile)
      end

      it "does not automatically set as default" do
        described_class.register(:production,
                                 token: "TEST_TOKEN",
                                 dev_channel: "C123",
                                 channels: {},
                                 user_groups: {})

        expect do
          described_class.default_profile
        end.to raise_error(SlackSender::Error, /No default profile set/)
      end

      it "raises error if profile already registered" do
        described_class.register(:production,
                                 token: "TEST_TOKEN",
                                 dev_channel: "C123",
                                 channels: {},
                                 user_groups: {})

        expect do
          described_class.register(:production,
                                   token: "OTHER_TOKEN",
                                   dev_channel: "C456",
                                   channels: {},
                                   user_groups: {})
        end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
      end
    end
  end

  describe ".call" do
    context "when default profile is set" do
      let(:profile) do
        described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )
      end

      before do
        profile
      end

      it "delegates to default_profile.call" do
        expect(described_class.default_profile).to receive(:call).with(channel: "C123", text: "test")
        described_class.call(channel: "C123", text: "test")
      end

      it "returns the result from profile.call" do
        allow(described_class.default_profile).to receive(:call).and_return(true)
        expect(described_class.call(channel: "C123", text: "test")).to be true
      end
    end

    context "when default profile is not set" do
      it "raises an error" do
        expect do
          described_class.call(channel: "C123", text: "test")
        end.to raise_error(SlackSender::Error, /No default profile set/)
      end
    end
  end

  describe ".call!" do
    context "when default profile is set" do
      let(:profile) do
        described_class.register(
          token: "TEST_TOKEN",
          dev_channel: "C123",
          channels: {},
          user_groups: {},
        )
      end

      before do
        profile
      end

      it "delegates to default_profile.call!" do
        expect(described_class.default_profile).to receive(:call!).with(channel: "C123", text: "test").and_return("123.456")
        expect(described_class.call!(channel: "C123", text: "test")).to eq("123.456")
      end
    end

    context "when default profile is not set" do
      it "raises an error" do
        expect do
          described_class.call!(channel: "C123", text: "test")
        end.to raise_error(SlackSender::Error, /No default profile set/)
      end
    end
  end

  describe ".[]" do
    let!(:profile) do
      described_class.register(:custom_profile,
                               token: "TEST_TOKEN",
                               dev_channel: "C123",
                               channels: {},
                               user_groups: {})
    end

    it "is an alias for .profile" do
      expect(described_class[:custom_profile]).to eq(profile)
    end

    it "returns the same profile as .profile" do
      expect(described_class[:custom_profile]).to eq(described_class.profile(:custom_profile))
    end

    it "raises ProfileNotFound for unknown profile" do
      expect { described_class[:unknown] }.to raise_error(SlackSender::ProfileNotFound)
    end
  end

  describe ".format_group_mention" do
    let!(:profile) do
      described_class.register(
        token: "TEST_TOKEN",
        dev_channel: "C123",
        channels: {},
        user_groups: { eng_team: "S123ABC", slack_development: "S_DEV" },
      )
    end

    before do
      allow(SlackSender.config).to receive(:in_production?).and_return(true)
    end

    it "delegates to default_profile.format_group_mention" do
      expect(described_class.format_group_mention(:eng_team)).to eq("<!subteam^S123ABC>")
    end

    context "when default profile is not set" do
      before do
        SlackSender::ProfileRegistry.clear!
      end

      it "raises an error" do
        expect do
          described_class.format_group_mention(:eng_team)
        end.to raise_error(SlackSender::Error, /No default profile set/)
      end
    end
  end
end
