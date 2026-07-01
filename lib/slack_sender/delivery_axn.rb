# frozen_string_literal: true

require_relative "delivery_axn/async_configuration"
require_relative "delivery_axn/exception_handlers"
require_relative "delivery_axn/error_message_parsing"
require_relative "delivery_axn/validation"

module SlackSender
  class DeliveryAxn
    include Axn

    # chat.postMessage keys SlackSender owns. slack_options may never set these — even when a
    # managed key is blank (and thus dropped by compact_blank), the passthrough must not fill it.
    MANAGED_POST_MESSAGE_KEYS = %i[channel text blocks attachments icon_emoji thread_ts].freeze

    # Class method modules (extend)
    extend AsyncConfiguration

    # Instance method modules (include)
    include ExceptionHandlers
    include ErrorMessageParsing
    include Validation

    # Base/headline message. axn prefixes every failure *reason* with this as
    # "Unable to send Slack message: <reason>", and uses it standalone as result.error for any
    # unexpected error that has no specific reason handler (instead of axn's generic "Something
    # went wrong"). It only affects the error-message *presentation* — classification, retries,
    # and on_exception reporting are unchanged.
    error "Unable to send Slack message"

    # Surface the underlying SlackSender::Error's message on result.error so it gets the base
    # prefix too (InvalidArgumentsError, the re-raised missing-scope error, etc.). A direct raise
    # matches on the exception itself; one raised from a preprocess lambda arrives wrapped in an
    # Axn::ContractViolation::PreprocessingError, so #unwrapped_slack_error unwraps the cause. One
    # resolver handles both cases, so there is no ordering dependency between separate handlers.
    # Message presentation only — these stay exception-bucket (still reported + retried like any
    # other StandardError).
    error(if: ->(exception:) { unwrapped_slack_error(exception) }) { |exception| unwrapped_slack_error(exception).message }

    expects :profile, type: Profile, preprocess: lambda { |p|
      # If given a string/symbol (profile name), look it up in the registry
      # Otherwise, assume it's already a Profile object
      p.is_a?(Profile) ? p : ProfileRegistry.find(p)
    }
    expects :validate_known_channel, type: :boolean, default: false
    expects :channel, type: String, preprocess: lambda { |ch|
      # NOTE: symbols are preprocessed to strings in Profile#preprocess_call_kwargs
      return ch unless validate_known_channel

      profile.channels[ch.to_sym] or raise InvalidArgumentsError, format(ErrorMessages::UNKNOWN_CHANNEL, ch)
    }
    expects :text, type: String, optional: true, preprocess: lambda { |txt|
      # Preserve blank strings so we can treat explicit blank text-only calls as no-ops
      # (rather than collapsing them into "no content provided").
      txt.present? ? ::Slack::Messages::Formatting.markdown(txt) : txt
    }
    expects :icon_emoji, type: String, optional: true, preprocess: lambda { |raw|
      normalize_icon_emoji(raw)
    }
    expects :blocks, type: Array, optional: true
    expects :attachments, type: Array, optional: true
    expects :thread_ts, type: String, optional: true
    expects :files, type: Array, optional: true, preprocess: lambda { |raw|
      MultiFileWrapper.new(raw).files
    }
    # file_ids is used for async file uploads: files are uploaded to Slack's servers
    # synchronously (returning file_ids), then the background job calls
    # files_completeUploadExternal to share them to the channel.
    # Array of hashes with "id" and "title" keys.
    expects :file_ids, type: Array, optional: true

    # Escape hatch: arbitrary chat.postMessage options forwarded straight to Slack
    # (e.g. unfurl_links:, unfurl_media:, reply_broadcast:, metadata:). Managed keys
    # (channel/text/blocks/attachments/icon_emoji/thread_ts) take precedence so sandbox
    # redirection and text formatting can't be clobbered. Applies to the text-post path only,
    # not file uploads (a different endpoint with a different option set).
    expects :slack_options, type: Hash, optional: true

    exposes :thread_ts, type: String, optional: true

    def call
      # Handle sandbox mode behavior
      return handle_sandbox_noop if sandbox_noop?

      has_files = files.present? || file_ids.present?
      has_files ? upload_files : post_message
    rescue Slack::Web::Api::Errors::MissingScope => e
      reraise_missing_scope_with_details(e)
    rescue Slack::Web::Api::Errors::IsArchived => e
      raise(e) unless SlackSender.config.silence_archived_channel_exceptions

      done! ErrorMessages::ARCHIVED_CHANNEL_SILENCED
    end

    private

    def normalize_icon_emoji(raw)
      ":#{raw}:".squeeze(":") if raw.present?
    end

    def client = profile.client

    # Profile configs
    def slack_client_config = profile.slack_client_config
    def sandbox_channel = profile.sandbox_channel

    # Sandbox behavior handling
    def effective_sandbox_behavior
      return nil unless SlackSender.config.sandbox_mode?

      profile.resolved_sandbox_behavior
    end

    def sandbox_noop? = effective_sandbox_behavior == :noop
    def sandbox_redirect? = effective_sandbox_behavior == :redirect
    def sandbox_passthrough? = effective_sandbox_behavior == :passthrough || effective_sandbox_behavior.nil?

    def handle_sandbox_noop
      log_sandbox_noop
      done! "Sandbox mode :noop - message not sent"
    end

    def log_sandbox_noop
      text_preview = text.to_s.truncate(100)
      log_message = format(ErrorMessages::SANDBOX_NOOP_LOG, profile.key, channel_display, text_preview)
      self.class.info(log_message)
    end

    # Channel resolution
    memo def channel_to_use = sandbox_redirect? ? sandbox_channel : channel
    memo def text_to_use
      return text unless sandbox_redirect?

      formatted_message = text&.lines&.map { |line| "> #{line}" }&.join

      [
        sandbox_channel_message_prefix,
        formatted_message,
      ].compact_blank.join("\n\n")
    end

    # Sandbox channel redirection - helpers
    def channel_display = channel_id?(channel) ? Slack::Messages::Formatting.channel_link(channel) : "`#{channel}`"

    def sandbox_channel_message_prefix
      format(profile.sandbox_channel_message_prefix.presence || ErrorMessages::DEFAULT_SANDBOX_CHANNEL_MESSAGE_PREFIX,
             channel_display)
    end

    # TODO: this is directionally correct, but more-correct would involve conversations.list
    def channel_id?(given)
      given[0] != "#" && given.match?(/\A[CGDZ][A-Z0-9]+\z/)
    end

    # Core sending methods
    def upload_files
      if file_ids.present?
        # Async path: complete pre-uploaded files (uploaded via FileUploader)
        complete_preuploaded_files
      else
        # Sync path: use files_upload_v2 for the full upload flow
        upload_files_v2
      end
    end

    # Completes files that were pre-uploaded to Slack's servers via FileUploader.
    # Called from background jobs where file_ids were passed instead of file content.
    def complete_preuploaded_files
      validate_channel_id_for_file_upload!

      response = client.files_completeUploadExternal(
        files: file_ids.to_json,
        channel_id: channel_to_use,
        initial_comment: text_to_use,
      )

      extract_thread_ts_from_complete_response(response)
    end

    # Uses files_upload_v2 for synchronous file uploads (call! path).
    def upload_files_v2
      validate_channel_id_for_file_upload!

      file_uploads = files.map(&:to_h)
      response = client.files_upload_v2(
        files: file_uploads,
        channel: channel_to_use,
        initial_comment: text_to_use,
      )

      extract_thread_ts_from_upload_response(response)
    end

    # Slack's files_upload_v2 API requires channel IDs (e.g., C024BE91L, D032AC32T),
    # not usernames (@user) or channel names (#channel). This is a limitation of
    # the newer Slack file upload APIs.
    def validate_channel_id_for_file_upload!
      ch = channel_to_use
      return if channel_id?(ch)

      raise InvalidArgumentsError, format(ErrorMessages::FILE_UPLOAD_REQUIRES_CHANNEL_ID, ch)
    end

    def extract_thread_ts_from_complete_response(response)
      # files_completeUploadExternal returns files array with shares info
      file_obj = response.dig("files", 0)
      return unless file_obj

      ts = file_obj.dig("shares", "public", channel_to_use, 0, "ts") ||
           file_obj.dig("shares", "private", channel_to_use, 0, "ts")
      expose thread_ts: ts if ts
    end

    def extract_thread_ts_from_upload_response(response)
      # files_upload_v2 doesn't return thread_ts directly, so we fetch it via files.info
      file_id = response.dig("files", 0, "id")
      return unless file_id

      file_info = client.files_info(file: file_id)
      ts = file_info.dig("file", "shares", "public", channel_to_use, 0, "ts") ||
           file_info.dig("file", "shares", "private", channel_to_use, 0, "ts")
      expose thread_ts: ts if ts
    end

    def post_message
      params = {
        channel: channel_to_use,
        text: text_to_use,
        blocks:,
        attachments:,
        icon_emoji:,
        thread_ts:,
      }.compact_blank

      # Merge caller passthrough options. Managed keys always win: strip them from the passthrough
      # first, so a blank managed key (dropped by compact_blank above) can't be shadowed by a
      # same-named slack_options key. deep_symbolize_keys mirrors the deep_stringify_keys applied at
      # enqueue (Profile#normalize_for_async_serialization!), so nested option hashes (e.g. metadata:)
      # round-trip with symbol keys intact rather than staying string-keyed after the async hop.
      if slack_options.present?
        passthrough = slack_options.deep_symbolize_keys.except(*MANAGED_POST_MESSAGE_KEYS)
        params = passthrough.merge(params)
      end

      response = client.chat_postMessage(**params)
      expose thread_ts: response["ts"]
    end

    # Returns the SlackSender::Error carried by an exception — the exception itself, or the
    # unwrapped cause of an Axn preprocessing wrapper — or nil if there is none.
    def unwrapped_slack_error(exception)
      return exception if exception.is_a?(SlackSender::Error)
      return exception.cause if exception.is_a?(Axn::ContractViolation::PreprocessingError) && exception.cause.is_a?(SlackSender::Error)

      nil
    end
  end
end
