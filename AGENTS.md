# AGENTS.md

Ruby gem for Slack messaging: background dispatch, retries, sandbox redirection, multi-profile.
Core action `DeliveryAxn`, `Notifier` base class, `use :slack` strategy — built on
[Axn](https://github.com/teamshares/axn).

## Axn

Before touching `DeliveryAxn`/`Notifier`/`Strategy`/`error`/`success`/`fail!`/`done!`: run
`bundle show axn`, read `AGENTS-consuming.md` there (contract, result/failure semantics, message
base/reason prefixing).

## Rules

- TDD: failing test first.
- No hard Rails dependency — guard `Rails`/`ActiveRecord`/`ActiveJob` refs with `defined?(...)`.
- `bundle exec rake` (rspec + rubocop) before done.
- `Gemfile.lock` is gitignored; CI always resolves fresh. `axn` is pinned to `branch: "main"` —
  re-run tests after `bundle update axn` if it may have moved.

## Error/success message wording

`DeliveryAxn` declares base `error "Unable to send Slack message"` (prefixes every reason on
`result.error`). `ErrorMessages` constants raised inside `DeliveryAxn`/its resolvers: bare reason,
no lead-in. Constants raised outside any Axn (`Profile`, `FileUploader`, `MultiFileWrapper`):
self-contained sentence. A constant shared by both call sites (e.g. `MISSING_SCOPE`) must read
correctly either way.

## Keep in sync on behavior changes

`README.md` (Features list only), `docs/*.md` (including quoted error strings), `CHANGELOG.md`
(`[Unreleased]`, flag behavior changes explicitly).
