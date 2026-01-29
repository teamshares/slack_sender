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
    DEFAULT_SANDBOX_CHANNEL_MESSAGE_PREFIX = ":construction: _This message would have been sent to %s in production_"
    PROFILE_UNREGISTERED = "Cannot specify profile: :%s when calling on unregistered profile. " \
                           "Register the profile first with SlackSender.register(name, config)"
    PROFILE_MISMATCH = "Cannot specify profile: :%s when calling on profile :%s. Use SlackSender.profile(:%s).call(...) instead"

    # Sandbox mode errors
    SANDBOX_REDIRECT_REQUIRES_CHANNEL = "Sandbox mode :redirect requires sandbox.channel.replace_with to be set"
    SANDBOX_NOOP_LOG = "[SANDBOX NOOP] Profile: %s | Channel: %s | Text: %s"

    # File size errors
    FILE_EXCEEDS_SLACK_LIMIT = "File '%s' (%s bytes) exceeds Slack's maximum file size of 1 GB"
    FILES_EXCEED_ASYNC_LIMIT = "Total file size (%s bytes) exceeds max_async_file_upload_size (%s bytes). " \
                               "Use SlackSender.call! for synchronous upload, or increase config.max_async_file_upload_size"

    # Slack API scope errors
    MISSING_SCOPE = "Slack API missing_scope error: required scope '%s' is not granted. " \
                    "Add this scope to your Slack app at https://api.slack.com/apps and reinstall the app."
    MISSING_SCOPE_UNKNOWN = "Slack API missing_scope error (scope not specified in response). " \
                            "Check your Slack app's OAuth scopes at https://api.slack.com/apps"

    # File upload errors
    FILE_UPLOAD_REQUIRES_CHANNEL_ID = "File uploads require a channel ID (e.g., C024BE91L or D032AC32T), " \
                                      "not '%s'. Slack's files_upload_v2 API does not support usernames (@user) " \
                                      "or channel names (#channel). Use the channel/DM ID instead."

    # Argument validation errors
    UNKNOWN_KWARGS = "Unknown argument(s): %s. Valid arguments are: %s"
  end
end
