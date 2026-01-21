# frozen_string_literal: true

module SlackSender
  module ErrorMessages
    ARCHIVED_CHANNEL_SILENCED = "Failed successfully: ignoring 'is archived' error per config"
    NO_CONTENT_PROVIDED = "Must provide at least one of: text, blocks, attachments, or files"
    INVALID_BLOCKS = "Provided blocks were invalid"
    FILES_WITH_BLOCKS = "Cannot provide files with blocks"
    FILES_WITH_ATTACHMENTS = "Cannot provide files with attachments"
    FILES_WITH_ICON_EMOJI = "Cannot provide files with icon_emoji"
    UNKNOWN_CHANNEL = "Unknown channel provided: :%s"
    DEFAULT_DEV_CHANNEL_REDIRECT_PREFIX = ":construction: _This message would have been sent to %s in production_"
    PROFILE_UNREGISTERED = "Cannot specify profile: :%s when calling on unregistered profile. " \
                           "Register the profile first with SlackSender.register(name, config)"
    PROFILE_MISMATCH = "Cannot specify profile: :%s when calling on profile :%s. Use SlackSender.profile(:%s).call(...) instead"
  end
end
