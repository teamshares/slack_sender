# frozen_string_literal: true

RSpec.describe SlackSender::ChannelNormalizer do
  describe "#initialize" do
    context "with channel: only" do
      subject(:normalizer) { described_class.new(channel: :general) }

      it { is_expected.to be_single }
      it { is_expected.not_to be_multi }

      it "stores the channel" do
        expect(normalizer.channel).to eq(:general)
      end

      it "has nil channels" do
        expect(normalizer.channels).to be_nil
      end
    end

    context "with channels: (multiple)" do
      subject(:normalizer) { described_class.new(channels: %i[alerts ops]) }

      it { is_expected.not_to be_single }
      it { is_expected.to be_multi }

      it "stores the channels array" do
        expect(normalizer.channels).to eq(%i[alerts ops])
      end

      it "has nil channel" do
        expect(normalizer.channel).to be_nil
      end
    end

    context "with channels: (single-element array)" do
      subject(:normalizer) { described_class.new(channels: [:alerts]) }

      it "normalizes to single channel" do
        expect(normalizer.channel).to eq(:alerts)
        expect(normalizer.channels).to be_nil
      end

      it { is_expected.to be_single }
    end

    context "with both channel: and channels:" do
      it "raises ArgumentError" do
        expect do
          described_class.new(channel: :general, channels: [:alerts])
        end.to raise_error(ArgumentError, /Cannot provide both channel: and channels:/)
      end
    end

    context "with empty channels:" do
      it "raises ArgumentError" do
        expect do
          described_class.new(channels: [])
        end.to raise_error(ArgumentError, /channels: cannot be empty/)
      end
    end

    context "with neither channel: nor channels:" do
      subject(:normalizer) { described_class.new }

      it "has nil channel and channels" do
        expect(normalizer.channel).to be_nil
        expect(normalizer.channels).to be_nil
      end

      it { is_expected.to be_single }
    end
  end

  describe "#preprocess_channel!" do
    context "when channel is a symbol" do
      subject(:normalizer) { described_class.new(channel: :general) }

      before { normalizer.preprocess_channel! }

      it "converts symbol to string" do
        expect(normalizer.channel).to eq("general")
      end

      it "sets validate_known_channel to true" do
        expect(normalizer.validate_known_channel).to be true
      end
    end

    context "when channel is a string" do
      subject(:normalizer) { described_class.new(channel: "C123456") }

      before { normalizer.preprocess_channel! }

      it "leaves channel as string" do
        expect(normalizer.channel).to eq("C123456")
      end

      it "does not set validate_known_channel" do
        expect(normalizer.validate_known_channel).to be false
      end
    end

    context "when channel is nil" do
      subject(:normalizer) { described_class.new }

      before { normalizer.preprocess_channel! }

      it "leaves channel as nil" do
        expect(normalizer.channel).to be_nil
      end

      it "does not set validate_known_channel" do
        expect(normalizer.validate_known_channel).to be false
      end
    end
  end

  describe "#apply_default!" do
    context "when no channel specified" do
      subject(:normalizer) { described_class.new }

      it "applies the default channel" do
        normalizer.apply_default!(:default_channel)
        expect(normalizer.channel).to eq(:default_channel)
      end
    end

    context "when channel already specified" do
      subject(:normalizer) { described_class.new(channel: :explicit) }

      it "does not override" do
        normalizer.apply_default!(:default_channel)
        expect(normalizer.channel).to eq(:explicit)
      end
    end

    context "when channels already specified" do
      subject(:normalizer) { described_class.new(channels: %i[a b]) }

      it "does not apply default" do
        normalizer.apply_default!(:default_channel)
        expect(normalizer.channel).to be_nil
        expect(normalizer.channels).to eq(%i[a b])
      end
    end

    context "when default is nil" do
      subject(:normalizer) { described_class.new }

      it "does not apply nil default" do
        normalizer.apply_default!(nil)
        expect(normalizer.channel).to be_nil
      end
    end
  end

  describe "#to_kwargs" do
    context "with single channel (symbol, not preprocessed)" do
      subject(:normalizer) { described_class.new(channel: :general) }

      it "returns channel: kwarg" do
        expect(normalizer.to_kwargs).to eq(channel: :general)
      end
    end

    context "with single channel (preprocessed symbol)" do
      subject(:normalizer) { described_class.new(channel: :general) }

      before { normalizer.preprocess_channel! }

      it "returns channel: and validate_known_channel:" do
        expect(normalizer.to_kwargs).to eq(channel: "general", validate_known_channel: true)
      end
    end

    context "with single channel (string)" do
      subject(:normalizer) { described_class.new(channel: "C123") }

      before { normalizer.preprocess_channel! }

      it "returns channel: without validate_known_channel" do
        expect(normalizer.to_kwargs).to eq(channel: "C123")
      end
    end

    context "with multiple channels" do
      subject(:normalizer) { described_class.new(channels: %i[a b]) }

      it "returns channels: kwarg" do
        expect(normalizer.to_kwargs).to eq(channels: %i[a b])
      end
    end

    context "with no channel" do
      subject(:normalizer) { described_class.new }

      it "returns empty hash" do
        expect(normalizer.to_kwargs).to eq({})
      end
    end
  end
end
