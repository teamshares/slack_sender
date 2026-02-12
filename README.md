# SlackSender

**Reliable Slack messaging for Ruby — with automatic retries, rate-limit handling, and sandbox safety.**

SlackSender handles the plumbing so you can focus on your application: background dispatch, retry logic, multi-workspace support, and development environment redirects are all built in.

## Installation

Add to your Gemfile:

```ruby
gem 'slack_sender'
```

Then run:

```bash
bundle install
```

**Requirements:**
- Ruby >= 3.2.1
- A Slack Bot User OAuth Token with `chat:write` scope (see [Configuration](docs/configuration.md#required-slack-scopes) for full scope list)
- For async delivery: Sidekiq or ActiveJob (auto-detected)

## Quick Start

### 1. Register a Profile

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: {
    ops_alerts: 'C1111111111',
    deployments: 'C2222222222',
  },
  sandbox: {
    channel: { replace_with: 'C_DEV_CHANNEL' }  # Redirects in non-production
  }
)
```

### 2. Send Messages

```ruby
# Async (recommended) — background job with automatic retries
SlackSender.call(channel: :ops_alerts, text: ":rotating_light: High error rate detected")

# Sync — when you need the thread timestamp
thread_ts = SlackSender.call!(channel: :deployments, text: ":rocket: Deploy started")
SlackSender.call(channel: :deployments, text: "Deploy complete!", thread_ts:)
```

That's it. SlackSender handles rate limits, retries, and sandbox redirection automatically.

## Documentation

| Guide | Description |
|-------|-------------|
| [Usage Guide](docs/usage.md) | Messages, files, threading, multi-channel delivery |
| [Configuration](docs/configuration.md) | Profiles, sandbox mode, global settings |
| [Axn Integration](docs/axn_integration.md) | `use :slack` strategy and `SlackSender::Notifier` |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and FAQ |

## Features

- **Background dispatch** with automatic rate-limit retries via Sidekiq or ActiveJob
- **Multi-channel delivery** — broadcast to multiple channels efficiently
- **Sandbox mode** — redirect or suppress messages in non-production environments
- **File uploads** — sync and async, with automatic size handling
- **Multiple profiles** — manage multiple Slack workspaces
- **Axn integration** — `use :slack` strategy and dedicated `Notifier` base class

## Development

```bash
bin/setup        # Install dependencies
bundle exec rspec # Run tests
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/teamshares/slack_sender.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
# test
