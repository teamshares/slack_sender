# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module Validation
      def self.included(base)
        base.before do
          done! if explicit_blank_text_only?
          raise InvalidArgumentsError, ErrorMessages::NO_CONTENT_PROVIDED if content_blank?
          raise InvalidArgumentsError, ErrorMessages::INVALID_BLOCKS if blocks.present? && !blocks_valid?

          if files.present? || file_ids.present?
            raise InvalidArgumentsError, ErrorMessages::FILES_WITH_BLOCKS if blocks.present?
            raise InvalidArgumentsError, ErrorMessages::FILES_WITH_ATTACHMENTS if attachments.present?
            raise InvalidArgumentsError, ErrorMessages::FILES_WITH_ICON_EMOJI if icon_emoji.present?
          end
        end
      end

      private

      # slack_options are message *modifiers* (unfurl_links, metadata, …), not content, so they do
      # NOT count here: a call with no text/blocks/attachments/files is content-blank even when it
      # carries slack_options. Forwarding such a call to Slack would return no_text and burn async
      # retries on a deterministic failure, so we fail fast with NO_CONTENT_PROVIDED instead.
      def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank? && file_ids.blank?

      def explicit_blank_text_only?
        # Caller explicitly passed `text:` but it's blank, with no other content. Treat as an
        # intentional no-op so we don't error or retry on intent-only blank sends. But if
        # slack_options are present the caller clearly meant to send something, so fall through to
        # raise NO_CONTENT_PROVIDED rather than silently dropping the call.
        # Optional text is nil when omitted; preprocess returns "" when text: "" is passed.
        content_blank? && text.is_a?(String) && slack_options.blank?
      end

      # TODO: Add better validations against slack block kit API
      def blocks_valid?
        blocks.all? { |block| block.is_a?(Hash) && (block.key?(:type) || block.key?("type")) }
      end
    end
  end
end
