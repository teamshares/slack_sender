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

      def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank? && file_ids.blank?

      def explicit_blank_text_only?
        # Caller explicitly passed `text:` but it's blank, and no other content.
        # Optional text is nil when omitted; preprocess returns "" when text: "" is passed.
        # Treat as no-op so we don't error or retry on intent-only blank sends.
        content_blank? && text.is_a?(String)
      end

      # TODO: Add better validations against slack block kit API
      def blocks_valid?
        blocks.all? { |block| block.is_a?(Hash) && (block.key?(:type) || block.key?("type")) }
      end
    end
  end
end
