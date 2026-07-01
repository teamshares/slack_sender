# AGENTS.md

Guidance for agents working in **slack_sender**. Read before writing code.

## What this is

A Ruby gem for reliable Slack messaging (background dispatch, retries, sandbox redirection,
multi-profile support), built on [Axn](https://github.com/teamshares/axn) for its core action
(`DeliveryAxn`), `Notifier` base class, and `use :slack` strategy.

## Axn (service objects)

Before writing or modifying anything Axn-based (`DeliveryAxn`, `Notifier`, `Strategy`,
`error`/`success`/`fail!`/`done!` declarations), read the in-gem agent guide: run `bundle show axn`
and read `AGENTS-consuming.md` at that path. It covers the `expects`/`exposes`/`call` contract, how
results and failures surface, and the message base/reason prefixing model — the failure messages in
this gem depend on it directly (see below).

## Non-negotiables

- **TDD**: failing test first, then implementation. Bugfixes start with a reproducing test.
- **Works outside Rails** — guard every `Rails`/`ActiveRecord`/`ActiveJob` reference with
  `defined?(...)`.
- Before claiming done: `bundle exec rake` (rspec + rubocop). The pre-commit hook auto-fixes
  RuboCop offenses on staged `.rb` files, but don't rely on it — run it yourself first.
- **`Gemfile.lock` is gitignored.** CI always resolves fresh, so a green run locally on an old
  lockfile doesn't guarantee CI is green — re-run after `bundle update` if a dependency (esp. `axn`,
  currently pinned to `branch: "main"`) may have moved.

## Error/success messages

`DeliveryAxn` declares a base `error "Unable to send Slack message"` — every failure reason renders
as `"Unable to send Slack message: <reason>"`, and this is what a caller sees on `result.error`.
Constants in `ErrorMessages` that are raised **inside** `DeliveryAxn` (or reached via its `error(if:
...)` resolvers) should read as a bare reason (no leading "Slack API ... error:" or similar), since
the base supplies the sentence's subject. Constants also raised **outside** any Axn (`Profile`,
`FileUploader`, `MultiFileWrapper` — the async pre-upload path) must be self-contained complete
sentences, since there's no base to attach to. A constant shared by both call sites (e.g.
`MISSING_SCOPE`) must read correctly either way — check both, and check `docs/troubleshooting.md`
for a copy of the wording.

## Docs to keep in sync

- `README.md` — Features list only; point elsewhere for detail.
- `docs/usage.md`, `docs/configuration.md`, `docs/axn_integration.md`, `docs/troubleshooting.md` —
  user-facing detail, including any literal error-message wording quoted there.
- `CHANGELOG.md` — every user-visible change, under `[Unreleased]` until versioned. Mark **Behavior
  change** explicitly when existing callers could observe a different string/exception.

A behavior change to error/success wording, sandbox handling, or the kwarg contract almost always
touches more than one of these — check all four before calling a change done.
