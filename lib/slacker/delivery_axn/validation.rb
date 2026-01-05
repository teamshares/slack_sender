# frozen_string_literal: true

module Slacker
  class DeliveryAxn
    module Validation
      def self.included(base)
        base.before do
          # Resolve channel symbol to ID using profile's channels
          @resolved_channel = resolve_channel(channel)
          fail! "channel must resolve to a String" unless @resolved_channel.is_a?(String)

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

      def resolve_channel(raw)
        return raw unless raw.is_a?(Symbol)

        profile.channels[raw] || fail!("Unknown channel: #{raw}")
      end

      def content_blank? = text.blank? && blocks.blank? && attachments.blank? && files.blank?

      def blocks_valid?
        return false if blocks.blank?

        return true if blocks.all? do |single_block|
          # TODO: Add better validations against slack block kit API
          single_block.is_a?(Hash) && (single_block.key?(:type) || single_block.key?("type"))
        end

        false
      end
    end
  end
end
