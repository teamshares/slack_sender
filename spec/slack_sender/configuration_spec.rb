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

  describe "#use_slack_notifiers_namespace" do
    it "defaults to true" do
      expect(config.use_slack_notifiers_namespace).to be true
    end

    it "can be set to false" do
      config.use_slack_notifiers_namespace = false
      expect(config.use_slack_notifiers_namespace).to be false
    end

    it "can be set to true explicitly" do
      config.use_slack_notifiers_namespace = true
      expect(config.use_slack_notifiers_namespace).to be true
    end
  end

  describe "#sandbox_mode?" do
    context "when @sandbox_mode is explicitly set" do
      it "returns true when set to true" do
        config.sandbox_mode = true
        expect(config.sandbox_mode?).to be true
      end

      it "returns false when set to false" do
        config.sandbox_mode = false
        expect(config.sandbox_mode?).to be false
      end
    end

    context "when reset to nil after an explicit value" do
      before { hide_const("Rails") }

      it "re-derives the default rather than storing nil (no silent sandbox disable)" do
        config.sandbox_mode = false
        config.sandbox_mode = nil
        expect(config.sandbox_mode?).to be true
      end

      it "clears the stored value so the reader returns the default, not nil" do
        config.sandbox_mode = true
        config.sandbox_mode = nil
        expect(config.sandbox_mode).to be true
      end
    end

    context "when @sandbox_mode is nil (default)" do
      context "when Rails is defined" do
        before do
          stub_const("Rails", double(env: double(production?: rails_production)))
        end

        context "in Rails production" do
          let(:rails_production) { true }

          it { expect(config.sandbox_mode?).to be false }
        end

        context "in Rails non-production" do
          let(:rails_production) { false }

          it { expect(config.sandbox_mode?).to be true }
        end
      end

      context "when Rails is not defined" do
        before do
          hide_const("Rails")
        end

        it { expect(config.sandbox_mode?).to be true }
      end
    end

    context "as a per-class overridable setting" do
      let(:action_class) { Class.new.include(Axn) }

      it "resolves the global value when no per-class override is set" do
        allow(SlackSender.config).to receive(:sandbox_mode).and_return(true)
        expect(described_class.resolve_override_for(action_class, :sandbox_mode)).to be true
      end

      it "resolves a per-class override set via configure(:slack_sender)" do
        action_class.configure(:slack_sender) { |c| c.sandbox_mode = false }
        expect(described_class.resolve_override_for(action_class, :sandbox_mode)).to be false
      end

      describe ".class_override" do
        it "reports [false, nil] when the class declares no override" do
          expect(described_class.class_override(action_class, :sandbox_mode)).to eq([false, nil])
        end

        it "reports [true, value] — including an explicit false — when overridden" do
          action_class.configure(:slack_sender) { |c| c.sandbox_mode = false }
          expect(described_class.class_override(action_class, :sandbox_mode)).to eq([true, false])
        end

        it "finds an override declared on an ancestor" do
          action_class.configure(:slack_sender) { |c| c.sandbox_mode = false }
          expect(described_class.class_override(Class.new(action_class), :sandbox_mode)).to eq([true, false])
        end

        it "returns [false, nil] for a non-class origin" do
          expect(described_class.class_override("not a class", :sandbox_mode)).to eq([false, nil])
        end
      end
    end
  end

  describe "#sandbox_default_behavior" do
    it "defaults to :noop" do
      expect(config.sandbox_default_behavior).to eq(:noop)
    end

    it "accepts :noop" do
      config.sandbox_default_behavior = :noop
      expect(config.sandbox_default_behavior).to eq(:noop)
    end

    it "accepts :redirect" do
      config.sandbox_default_behavior = :redirect
      expect(config.sandbox_default_behavior).to eq(:redirect)
    end

    it "accepts :passthrough" do
      config.sandbox_default_behavior = :passthrough
      expect(config.sandbox_default_behavior).to eq(:passthrough)
    end

    it "raises ArgumentError for unsupported behavior" do
      expect { config.sandbox_default_behavior = :unknown }.to raise_error(
        ArgumentError,
        /sandbox_default_behavior must be one of.*got :unknown/,
      )
    end

    it "includes supported behaviors in error message" do
      expect { config.sandbox_default_behavior = :invalid }.to raise_error(
        ArgumentError,
        /must be one of :noop, :redirect, :passthrough/,
      )
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

  describe "#max_async_file_upload_size" do
    it "defaults to 25 MB" do
      expect(config.max_async_file_upload_size).to eq(26_214_400)
    end

    it "can be set to a custom value" do
      config.max_async_file_upload_size = 50_000_000
      expect(config.max_async_file_upload_size).to eq(50_000_000)
    end

    it "accepts nil to disable the limit" do
      config.max_async_file_upload_size = nil
      expect(config.max_async_file_upload_size).to be_nil
    end

    it "accepts zero" do
      config.max_async_file_upload_size = 0
      expect(config.max_async_file_upload_size).to eq(0)
    end

    it "raises ArgumentError for negative values" do
      expect { config.max_async_file_upload_size = -1 }.to raise_error(
        ArgumentError,
        /max_async_file_upload_size must be a non-negative integer or nil/,
      )
    end

    it "raises ArgumentError when exceeding Slack's 1 GB limit" do
      expect { config.max_async_file_upload_size = 2_000_000_000 }.to raise_error(
        ArgumentError,
        /cannot exceed Slack's maximum file size.*1 GB/,
      )
    end

    it "accepts exactly Slack's 1 GB limit" do
      config.max_async_file_upload_size = described_class::SLACK_MAX_FILE_SIZE
      expect(config.max_async_file_upload_size).to eq(1_073_741_824)
    end
  end

  describe "SLACK_MAX_FILE_SIZE constant" do
    it "is 1 GB" do
      expect(described_class::SLACK_MAX_FILE_SIZE).to eq(1_073_741_824)
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
