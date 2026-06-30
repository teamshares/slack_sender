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
- Requires a release of upstream `axn` that includes `Axn::Configurable` (PRO-2769) and the error
  message presentation behavior from PRO-2820 (#132) and PRO-2832 (#134) — the base/reason prefix
  and nested-`call!` header aggregation that the base-message behavior below relies on.
- **Behavior change:** failed deliveries now carry a consistent base message on `result.error`.
  Every failure reason is prefixed as `"Unable to send Slack message: <reason>"`, and unexpected
  errors with no specific reason handler surface `"Unable to send Slack message"` instead of axn's
  generic `"Something went wrong"`. This is presentation-only — error classification, retries, and
  exception reporting are unchanged. The `MISSING_SCOPE`/`MISSING_SCOPE_UNKNOWN` messages were
  rewritten as complete, self-contained sentences (`"Missing required Slack scope '%s'. ..."`) so
  they read cleanly both prefixed by the base (`DeliveryAxn`'s text-post path) and standalone
  (`FileUploader`'s async pre-upload path, which has no base to attach to).
- Add a `slack_options:` passthrough hash for forwarding arbitrary `chat.postMessage` options
  (`unfurl_links`, `unfurl_media`, `reply_broadcast`, `metadata`, …) straight to Slack. Managed
  keys (channel/text/blocks/attachments/icon_emoji/thread_ts) take precedence; applies to the
  text-post path only, not file uploads.

## [0.1.0] - 2026-02-19

- Initial release
