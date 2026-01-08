# frozen_string_literal: true

RSpec.describe SlackSender::Configuration do
  subject(:config) { described_class.new }

  describe "#enabled" do
    it "defaults to true" do
      expect(config.enabled).to be true
    end

    it "can be set to false" do
      config.enabled = false
      expect(config.enabled).to be false
    end
  end

  describe "#silence_archived_channel_exceptions" do
    it "defaults to nil" do
      expect(config.silence_archived_channel_exceptions).to be_nil
    end

    it "can be set" do
      config.silence_archived_channel_exceptions = true
      expect(config.silence_archived_channel_exceptions).to be true
    end
  end

  describe "#in_production?" do
    context "when @in_production is explicitly set" do
      it "returns true when set to true" do
        config.in_production = true
        expect(config.in_production?).to be true
      end

      it "returns false when set to false" do
        config.in_production = false
        expect(config.in_production?).to be false
      end
    end

    context "when @in_production is nil (default)" do
      context "when Rails is defined" do
        before do
          stub_const("Rails", double(env: double(production?: rails_production)))
        end

        context "in Rails production" do
          let(:rails_production) { true }

          it { expect(config.in_production?).to be true }
        end

        context "in Rails non-production" do
          let(:rails_production) { false }

          it { expect(config.in_production?).to be false }
        end
      end

      context "when Rails is not defined" do
        before do
          hide_const("Rails")
        end

        it { expect(config.in_production?).to be false }
      end
    end
  end

  describe "#async_backend" do
    context "when not explicitly set" do
      context "with Sidekiq::Job defined" do
        before do
          stub_const("Sidekiq::Job", Class.new)
          hide_const("ActiveJob::Base") if defined?(ActiveJob::Base)
        end

        it "auto-detects :sidekiq" do
          expect(described_class.new.async_backend).to eq(:sidekiq)
        end
      end

      context "with ActiveJob::Base defined (no Sidekiq)" do
        before do
          hide_const("Sidekiq::Job") if defined?(Sidekiq::Job)
          stub_const("ActiveJob::Base", Class.new)
        end

        it "auto-detects :active_job" do
          expect(described_class.new.async_backend).to eq(:active_job)
        end
      end

      context "with both Sidekiq and ActiveJob defined" do
        before do
          stub_const("Sidekiq::Job", Class.new)
          stub_const("ActiveJob::Base", Class.new)
        end

        it "prefers :sidekiq" do
          expect(described_class.new.async_backend).to eq(:sidekiq)
        end
      end

      context "with neither defined" do
        before do
          hide_const("Sidekiq::Job") if defined?(Sidekiq::Job)
          hide_const("ActiveJob::Base") if defined?(ActiveJob::Base)
        end

        it "returns nil" do
          expect(described_class.new.async_backend).to be_nil
        end
      end
    end

    context "when explicitly set" do
      it "accepts :sidekiq" do
        config.async_backend = :sidekiq
        expect(config.async_backend).to eq(:sidekiq)
      end

      it "accepts :active_job" do
        config.async_backend = :active_job
        expect(config.async_backend).to eq(:active_job)
      end

      it "accepts nil to reset to auto-detection" do
        # First set to a specific backend
        config.async_backend = :active_job
        expect(config.async_backend).to eq(:active_job)

        # Then set to nil - triggers re-detection
        # Since Sidekiq is loaded in test env, it will auto-detect :sidekiq
        config.async_backend = nil
        # The getter uses ||= so nil triggers auto-detection again
        expect(config.async_backend).to eq(:sidekiq)
      end

      it "raises ArgumentError for unsupported backend" do
        expect { config.async_backend = :resque }.to raise_error(
          ArgumentError,
          /Unsupported async backend: :resque/,
        )
      end

      it "includes supported backends in error message" do
        expect { config.async_backend = :delayed_job }.to raise_error(
          ArgumentError,
          /Supported backends: \[:sidekiq, :active_job\]/,
        )
      end
    end
  end

  describe "#async_backend_available?" do
    context "when async_backend is nil" do
      before do
        hide_const("Sidekiq::Job") if defined?(Sidekiq::Job)
        hide_const("ActiveJob::Base") if defined?(ActiveJob::Base)
      end

      subject(:config) { described_class.new }

      it { expect(config.async_backend_available?).to be false }
    end

    context "when async_backend is :sidekiq" do
      before { config.async_backend = :sidekiq }

      context "with Sidekiq::Job defined" do
        before { stub_const("Sidekiq::Job", Class.new) }

        it { expect(config.async_backend_available?).to be_truthy }
      end

      context "without Sidekiq::Job defined" do
        before { hide_const("Sidekiq::Job") if defined?(Sidekiq::Job) }

        it { expect(config.async_backend_available?).to be_falsey }
      end
    end

    context "when async_backend is :active_job" do
      before { config.async_backend = :active_job }

      context "with ActiveJob::Base defined" do
        before { stub_const("ActiveJob::Base", Class.new) }

        it { expect(config.async_backend_available?).to be_truthy }
      end

      context "without ActiveJob::Base defined" do
        before { hide_const("ActiveJob::Base") if defined?(ActiveJob::Base) }

        it { expect(config.async_backend_available?).to be_falsey }
      end
    end
  end
end

RSpec.describe SlackSender do
  describe ".config" do
    it "returns a Configuration instance" do
      expect(described_class.config).to be_a(SlackSender::Configuration)
    end

    it "returns the same instance on subsequent calls" do
      expect(described_class.config).to be(described_class.config)
    end
  end

  describe ".configure" do
    it "yields the config object" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.config)
    end

    it "allows setting configuration values" do
      original_enabled = described_class.config.enabled

      described_class.configure do |config|
        config.enabled = !original_enabled
      end

      expect(described_class.config.enabled).to eq(!original_enabled)

      # Reset
      described_class.config.enabled = original_enabled
    end
  end
end
