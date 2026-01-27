# frozen_string_literal: true

RSpec.describe SlackSender::ProfileRegistry do
  after do
    described_class.clear!
  end

  describe ".register" do
    it "registers a profile with the given name" do
      profile = described_class.register(:test_profile,
                                         token: "TEST_TOKEN",
                                         sandbox: { channel: { replace_with: "C123" } })

      expect(profile).to be_a(SlackSender::Profile)
      expect(described_class.find(:test_profile)).to eq(profile)
    end

    it "allows sandbox to be empty" do
      profile = described_class.register(:test_profile,
                                         token: "TEST_TOKEN")

      expect(profile.sandbox_channel).to be_nil
    end

    it "defaults channels and user_groups to empty hashes" do
      profile = described_class.register(:test_profile,
                                         token: "TEST_TOKEN")

      expect(profile.channels).to eq({})
      expect(profile.user_groups).to eq({})
    end

    it "raises error if profile already exists" do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               sandbox: { channel: { replace_with: "C123" } })

      expect do
        described_class.register(:test_profile,
                                 token: "OTHER_TOKEN",
                                 sandbox: { channel: { replace_with: "C456" } })
      end.to raise_error(SlackSender::DuplicateProfileError, /already registered/)
    end
  end

  describe ".find" do
    before do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               sandbox: { channel: { replace_with: "C123" } })
    end

    it "finds a registered profile" do
      profile = described_class.find(:test_profile)
      expect(profile).to be_a(SlackSender::Profile)
      expect(profile.sandbox_channel).to eq("C123")
    end

    it "raises error if profile not found" do
      expect do
        described_class.find(:nonexistent)
      end.to raise_error(SlackSender::ProfileNotFound, /not found/)
    end

    it "raises error if name is nil" do
      expect do
        described_class.find(nil)
      end.to raise_error(SlackSender::ProfileNotFound, /cannot be nil/)
    end

    it "raises error if name is empty" do
      expect do
        described_class.find("")
      end.to raise_error(SlackSender::ProfileNotFound, /cannot be empty/)
    end
  end

  describe ".clear!" do
    before do
      described_class.register(:test_profile,
                               token: "TEST_TOKEN",
                               sandbox: { channel: { replace_with: "C123" } })
    end

    it "clears all registered profiles" do
      described_class.clear!
      expect(described_class.all).to be_empty
    end
  end
end
