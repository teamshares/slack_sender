## [Unreleased]

## [0.1.1] - 2026-08-05

- `sandbox_mode` is now a per-class-overridable setting. An Axn action using the `:slack` strategy
  can opt in/out of sandbox for its own sends via `configure(:slack_sender) { |c| c.sandbox_mode = false }`
  (the axn `PRO-2880` namespaced-config DSL); the override is resolved at the origin action when it
  sends, threaded down to `DeliveryAxn`, and inherits into subclasses. Actions that declare none are
  unaffected and follow global config. Applies to the strategy delivery path only, not
  `SlackSender.group_link`. Internally, `Configuration#sandbox_mode` moved to the `Axn::Configurable`
  DSL (a dynamic Proc `default:` preserving the `Rails.env`-derived behavior); `sandbox_mode?` is unchanged.
  `sandbox_mode?` is now the DSL-generated predicate reader (PRO-2888) rather than a hand-written
  alias. Requires an `axn` with `Axn::Configurable` namespaced config (PRO-2880) and predicate
  readers (PRO-2888).
- Source `axn` from the published `0.1.0-alpha.5` release on RubyGems instead of the temporary
  `github: teamshares/axn, branch: main` git pin. The gemspec lower bound is now `>= 0.1.0-alpha.5`
  — the first release where a Proc `default:` is dynamic on its own (the `callable:` kwarg removed),
  which `Configuration#sandbox_mode` relies on. No behavior change.
- Adopt the upstream `Axn::Configurable::Settings` DSL for the simple, declarative
  `SlackSender::Configuration` settings (`enabled`, `silence_archived_channel_exceptions`,
  `sandbox_default_behavior`, `use_slack_notifiers_namespace`). Bespoke/computed settings
  (`sandbox_mode?`, `async_backend`, `max_async_file_upload_size`) remain hand-written.
- **Behavior change:** invalid `sandbox_default_behavior` values now raise the DSL's
  `ArgumentError` (`sandbox_default_behavior must be one of ...`) instead of the previous
  hand-written `Unsupported sandbox behavior` message. `Profile`'s per-profile
  `sandbox: { behavior: ... }` validation now shares `Configuration::SUPPORTED_SANDBOX_BEHAVIORS`
  and raises the matching wording (`sandbox.behavior must be one of ...`), so the two no longer
  diverge.
- Requires a release of upstream `axn` that includes `Axn::Configurable` (PRO-2769) and the error
  message presentation behavior from PRO-2820 (#132) and PRO-2832 (#134) — the base/reason prefix
  and nested-`call!` header aggregation that the base-message behavior below relies on. The gemspec
  runtime dependency lower bound is raised to `axn >= 0.1.0-alpha.5` accordingly (see the sourcing
  note above), so consumers can't resolve an older `axn` and `NameError` on `require`.
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
  text-post path only, not file uploads. Like `blocks`/`attachments`, `slack_options` is
  deep-stringified before an async job is enqueued, so a symbol-keyed hash (e.g.
  `slack_options: { unfurl_links: false }`) doesn't get rejected by Sidekiq's strict argument
  checks before the message is ever sent. A call with blank `text:` but a non-empty
  `slack_options:` (and no real content) now fails fast with the `NO_CONTENT_PROVIDED` validation
  error instead of being silently dropped as a no-op — `slack_options` are message modifiers, not
  content, so forwarding a content-less call to Slack would only return `no_text` and burn async
  retries. The error is an `InvalidArgumentsError`, so async jobs discard it rather than retrying.
  `slack_options` is also available in the `Notifier` `notify do … end` DSL
  (`slack_options unfurl_links: false`).
- **Behavior change:** async deliveries that fail argument validation inside a `preprocess` lambda
  (e.g. an unknown channel) are now discarded instead of retried. `axn` wraps such errors in an
  `Axn::ContractViolation::PreprocessingError`, so the previous `InvalidArgumentsError`-only
  Sidekiq `sidekiq_retry_in` / ActiveJob `discard_on` checks missed them and burned all 5 retries
  on a permanently-invalid job.

## [0.1.0] - 2026-02-19

- Initial release
