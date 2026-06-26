## [Unreleased]

* N/A

## [0.2.0] - 2026-06-26

- Adopt the upstream `Axn::Configurable::Settings` DSL for the simple, declarative
  `SlackSender::Configuration` settings (`enabled`, `silence_archived_channel_exceptions`,
  `sandbox_default_behavior`, `use_slack_notifiers_namespace`). Bespoke/computed settings
  (`sandbox_mode?`, `async_backend`, `max_async_file_upload_size`) remain hand-written.
- **Behavior change:** invalid `sandbox_default_behavior` values now raise the DSL's
  `ArgumentError` (`sandbox_default_behavior must be one of ...`) instead of the previous
  hand-written `Unsupported sandbox behavior` message.
- Requires a release of upstream `axn` that includes `Axn::Configurable` (PRO-2769).

## [0.1.0] - 2026-02-19

- Initial release
