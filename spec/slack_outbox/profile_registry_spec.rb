# frozen_string_literal: true

RSpec.describe SlackOutbox::ProfileRegistry do
  after do
    described_class.clear!
  end

  describe ".register" do
    it "registers a profile with the given name" do
      profile = described_class.register(:test_profile,
                                         token: "TEST_TOKEN",
                                         dev_channel: "C123",
                                         channels: {},
                                         user_groups: {})

      expect(profile).to be_a(SlackOutbox::Profile)
      expect(described_class.find(:test_profile)).to eq(profile)
    end

    it "allows dev_channel to be nil" do
      profile = described_class.register(:test_profile,
                                         token: "TEST_TOKEN",
                                         channels: {},
                                         user_groups: {})

      expect(profile.dev_channel).to be_nil
    end

    it "raises error if profile already exists" do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               dev_channel: "C123",
                               channels: {},
                               user_groups: {})

      expect do
        described_class.register(:test_profile,
                                 token: "OTHER_TOKEN",
                                 dev_channel: "C456",
                                 channels: {},
                                 user_groups: {})
      end.to raise_error(SlackOutbox::DuplicateProfileError, /already registered/)
    end
  end

  describe ".find" do
    before do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               dev_channel: "C123",
                               channels: {},
                               user_groups: {})
    end

    it "finds a registered profile" do
      profile = described_class.find(:test_profile)
      expect(profile).to be_a(SlackOutbox::Profile)
      expect(profile.dev_channel).to eq("C123")
    end

    it "raises error if profile not found" do
      expect do
        described_class.find(:nonexistent)
      end.to raise_error(SlackOutbox::ProfileNotFound, /not found/)
    end

    it "raises error if name is nil" do
      expect do
        described_class.find(nil)
      end.to raise_error(SlackOutbox::ProfileNotFound, /cannot be nil/)
    end

    it "raises error if name is empty" do
      expect do
        described_class.find("")
      end.to raise_error(SlackOutbox::ProfileNotFound, /cannot be empty/)
    end
  end

  describe ".clear!" do
    before do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               dev_channel: "C123",
                               channels: {},
                               user_groups: {})
    end

    it "clears all registered profiles" do
      described_class.clear!
      expect(described_class.all).to be_empty
    end
  end
end
