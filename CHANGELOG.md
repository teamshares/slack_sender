## [Unreleased]

* N/A

## [0.1.1] - 2026-06-26

- Adopt the upstream `Axn::Configurable::Settings` DSL for the simple, declarative
  `SlackSender::Configuration` settings (`enabled`, `silence_archived_channel_exceptions`,
  `sandbox_default_behavior`, `use_slack_notifiers_namespace`). Bespoke/computed settings
  (`sandbox_mode?`, `async_backend`, `max_async_file_upload_size`) remain hand-written.
- **Behavior change:** invalid `sandbox_default_behavior` values now raise the DSL's
  `ArgumentError` (`sandbox_default_behavior must be one of ...`) instead of the previous
  hand-written `Unsupported sandbox behavior` message.
- Requires a release of upstream `axn` that includes `Axn::Configurable` (PRO-2769).
- **Behavior change:** failed deliveries now carry a consistent base message on `result.error`.
  Every failure reason is prefixed as `"Unable to send Slack message: <reason>"`, and unexpected
  errors with no specific reason handler surface `"Unable to send Slack message"` instead of axn's
  generic `"Something went wrong"`. This is presentation-only — error classification, retries, and
  exception reporting are unchanged. The `MISSING_SCOPE`/`MISSING_SCOPE_UNKNOWN` messages dropped
  their `"Slack API missing_scope error:"` lead-in so they read cleanly under the new prefix.

## [0.1.0] - 2026-02-19

- Initial release
