# frozen_string_literal: true

module SlackSender
  class DeliveryAxn
    module Validation
      def self.included(base)
        base.before do
          fail! "Must provide at least one of: text, blocks, attachments, or files" if content_blank?
          fail! "Provided blocks were invalid" if blocks.present? && !blocks_valid?

          if files.present?
            fail! "Cannot provide files with blocks" if blocks.present?
            fail! "Cannot provide files with attachments" if attachments.present?
            fail! "Cannot provide files with icon_emoji" if icon_emoji.present?
          end
        end
      end

      private

      def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank?

      # TODO: Add better validations against slack block kit API
      def blocks_valid?
        blocks.all? { |block| block.is_a?(Hash) && (block.key?(:type) || block.key?("type")) }
      end
    end
  end
end
