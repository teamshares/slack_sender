# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module Validation
      def self.included(base)
        base.before do
          done! if explicit_blank_text_only?
          fail! ErrorMessages::NO_CONTENT_PROVIDED if content_blank?
          fail! ErrorMessages::INVALID_BLOCKS if blocks.present? && !blocks_valid?

          if files.present?
            fail! ErrorMessages::FILES_WITH_BLOCKS if blocks.present?
            fail! ErrorMessages::FILES_WITH_ATTACHMENTS if attachments.present?
            fail! ErrorMessages::FILES_WITH_ICON_EMOJI if icon_emoji.present?
          end
        end
      end

      private

      def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank?

      def explicit_blank_text_only?
        # If the caller explicitly passed `text:` but it is blank, treat it as a no-op
        # *only* when no other content keys were provided. This avoids enqueuing retries
        # for an input that can never succeed, while still failing true "no content" calls.
        Util.blank_text_only?(@__context&.provided_data || {})
      end

      # TODO: Add better validations against slack block kit API
      def blocks_valid?
        blocks.all? { |block| block.is_a?(Hash) && (block.key?(:type) || block.key?("type")) }
      end
    end
  end
end
