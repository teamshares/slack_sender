# SlackSender

**Background dispatch with automatic rate-limit retries -- Lazy at call time, diligent at delivery time.**

SlackSender provides a simple, reliable way to send Slack messages from Ruby applications. It handles rate limiting, retries, error notifications, and development environment redirects automatically.

## Summary

SlackSender is a Ruby gem that simplifies sending messages to Slack by:

- **Background dispatch** with automatic rate-limit retries via Sidekiq or ActiveJob
- **Development mode redirects** to prevent accidental production notifications
- **Automatic error handling** for common Slack API errors (NotInChannel, ChannelNotFound, IsArchived)
- **Multiple profile support** for managing multiple Slack workspaces
- **File upload support** with synchronous delivery
- **User group mention formatting** with development mode substitution

## Motivation

Sending Slack messages from Ruby applications often requires:
- Managing rate limits and retries manually
- Handling various Slack API errors
- Preventing accidental production notifications in development
- Coordinating multiple Slack workspaces or bots

SlackSender abstracts these concerns, allowing you to focus on your application logic while it handles the complexities of reliable Slack message delivery.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slack_sender'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install slack_sender
```

## Requirements

- Ruby >= 3.2.1
- A Slack API token (Bot User OAuth Token)
- For async delivery: Sidekiq or ActiveJob (auto-detected if available)

## Quick Start

### 1. Configure a Profile

Register a profile with your Slack token and channel configuration:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: {
    ops_alerts: 'C1111111111',
    deployments: 'C2222222222',
    reports: 'C3333333333',
  },
  user_groups: {
    engineers: 'S1234567890',
  },
  sandbox: {  # Optional: redirect messages/mentions when in sandbox mode (non-production)
    channel: {
      replace_with: 'C1234567890',
      message_prefix: ':construction: _This message would have been sent to %s in production_'
    },
    user_group: {
      replace_with: 'S_DEV_GROUP'
    }
  }
)
```

### 2. Send Messages

```ruby
# Async delivery (recommended) - uses Sidekiq or ActiveJob
SlackSender.call(
  channel: :ops_alerts,
  text: ":rotating_light: High error rate on checkout"
)

# Synchronous delivery (returns thread timestamp)
thread_ts = SlackSender.call!(
  channel: :deployments,
  text: ":rocket: Deploy finished for #{ENV.fetch('APP_NAME', 'my-app')} (#{Rails.env})"
)
```

**Note:** If `text:` is explicitly provided but blank (and you did not provide `blocks`, `attachments`, or `files`), SlackSender treats it as a no-op and returns `false` (it will not enqueue a job and will not send anything to Slack).

## Usage

### Basic Messages

```ruby
# Simple text message
SlackSender.call(
  channel: :ops_alerts,
  text: ":warning: Redis latency is elevated"
)

# With markdown formatting
SlackSender.call(
  channel: :deployments,
  text: "Deploy started by *#{user.name}* for `#{ENV.fetch('APP_NAME', 'my-app')}`"
)
```

**Note:** Text is parsed as [Slack mrkdwn](https://api.slack.com/reference/surfaces/formatting) by default. For formatting user mentions, channels, links, and other special content, use the `Slack::Messages::Formatting` helpers from [slack-ruby-client](https://github.com/slack-ruby/slack-ruby-client#message-formatting):

```ruby
SlackSender.call(
  channel: :ops_alerts,
  text: [
    ":rotating_light: Incident acknowledged by #{Slack::Messages::Formatting.user(user.slack_id)}",
    Slack::Messages::Formatting.url('https://status.example.com/incidents/123', 'Incident timeline'),
  ].join("\n")
)
```

### Channel Resolution

Channels can be specified as symbols (resolved from profile config) or channel IDs:

```ruby
# Using symbol (resolved from channels hash)
SlackSender.call(channel: :ops_alerts, text: ":rotating_light: Alert")

# Using channel ID directly
SlackSender.call(channel: "C1234567890", text: ":rotating_light: Alert")
```

### Default Channel

Configure a default channel for a profile to avoid passing `channel:` on every call:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  default_channel: :ops_alerts,  # Used when no channel is specified
  channels: {
    ops_alerts: 'C1111111111',
    deployments: 'C2222222222',
  }
)

# These are equivalent:
SlackSender.call(text: "Alert!")                    # Uses default_channel
SlackSender.call(channel: :ops_alerts, text: "Alert!") # Explicit channel

# Override when needed
SlackSender.call(channel: :deployments, text: "Hello") # Uses :deployments instead
```

The `default_channel` can be a symbol (resolved from `channels` hash) or a channel ID string.

### Rich Messages

```ruby
# With blocks
SlackSender.call(
  channel: :deployments,
  blocks: [
    {
      type: "section",
      text: { type: "mrkdwn", text: ":rocket: *Deploy finished* for `my-app`" }
    }
  ]
)

# With attachments
SlackSender.call(
  channel: :ops_alerts,
  attachments: [
    {
      color: "good",
      text: "Autoscaling event completed successfully"
    }
  ]
)

# With custom emoji
SlackSender.call(
  channel: :ops_alerts,
  text: "Background job queue is healthy",
  icon_emoji: "robot"
)
```

### File Uploads

File uploads are supported with synchronous delivery (`call!`). Note: file uploads are not yet supported with async delivery (feature planned post alpha release).

```ruby
# Single file
SlackSender.call!(
  channel: :reports,
  text: "Daily ops report attached",
  files: [File.open("report.pdf")]
)

# Multiple files
SlackSender.call!(
  channel: :reports,
  text: "Daily ops report (details + raw export)",
  files: [
    File.open("report.pdf"),
    File.open("data.csv")
  ]
)
```

**Note**: Filenames are automatically detected from file objects. For custom filenames, use objects that respond to `original_filename` (e.g., ActionDispatch::Http::UploadedFile) or ensure the file path contains the desired filename.

Supported file types:
- `File` objects
- `Tempfile` objects
- `StringIO` objects
- `ActiveStorage::Attachment` objects (if ActiveStorage is available)
- String file paths (will be opened automatically)
- Any object that responds to `read` and has `original_filename` or `path`

### Threading

```ruby
# Reply to a thread
SlackSender.call(
  channel: :ops_alerts,
  text: "Mitigation: rolled back to previous release",
  thread_ts: "1234567890.123456"
)

# Get thread timestamp from initial message
thread_ts = SlackSender.call!(
  channel: :ops_alerts,
  text: ":rotating_light: Elevated 500s detected on /checkout"
)
# thread_ts => "1234567890.123456"
```

### User Group Mentions

Format user group mentions (automatically redirects to sandbox user_group when in sandbox mode):

```ruby
SlackSender.format_group_mention(:on_call)
# => "<!subteam^S1234567890|@on_call>"
```

If `sandbox.user_group.replace_with` is configured and the app is in sandbox mode (per `config.sandbox_mode?`), `format_group_mention` will replace the requested group with the sandbox user_group instead, similar to how sandbox channel redirects messages:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  user_groups: {
    engineers: 'S1234567890',  # Would be replaced with sandbox user_group in sandbox mode
  },
  sandbox: {
    user_group: { replace_with: 'S_DEV_GROUP' }  # All group mentions use this in sandbox mode
  }
)

# In sandbox mode, this returns the sandbox user_group mention
SlackSender.format_group_mention(:engineers)
# => "<!subteam^S_DEV_GROUP>"
```

### Dynamic Token

Use a callable for the token to fetch it dynamically:

```ruby
SlackSender.register(
  token: -> { SecretsManager.get_slack_token },
  channels: { ops_alerts: 'C123' }
)
```

The token is memoized after first access, so the callable is only evaluated once per profile instance.

### Multiple Profiles

Register multiple profiles for different Slack workspaces:

```ruby
# Internal engineering workspace
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { ops_alerts: 'C123', deployments: 'C234' }
)

# Customer support workspace
SlackSender.register(:support,
  token: ENV['SUPPORT_SLACK_TOKEN'],
  channels: { support_tickets: 'C456' }
)

# Use specific profile
SlackSender.profile(:support).call(
  channel: :support_tickets,
  text: "New high-priority ticket received"
)

# Or use bracket notation
SlackSender[:support].call(
  channel: :support_tickets,
  text: "New high-priority ticket received"
)

# Or override default profile with profile parameter
SlackSender.call(
  profile: :support,
  channel: :support_tickets,
  text: "New high-priority ticket received"
)
```

## Axn Integration

SlackSender provides deep integration with [Axn](https://teamshares.github.io/axn/) for building Slack-enabled actions and dedicated notifier classes.

### Slack Strategy for Axn Actions

Add Slack messaging capabilities to any Axn action using the `:slack` strategy:

```ruby
class Deployments::Finish
  include Axn
  use :slack, channel: :deployments  # Default channel for all slack() calls

  expects :deployment, type: Deployment

  on_success { slack ":rocket: Deploy finished for `#{deployment.service}`" }
  on_failure { slack ":x: Deploy failed for `#{deployment.service}`", channel: :ops_alerts }

  def call
    slack "Finalizing deploy for `#{deployment.service}`..." # Uses default channel
    # ... rollout / status checks / persistence ...
  end
end
```

#### Strategy Configuration

```ruby
use :slack, channel: :general             # Default channel for all slack() calls
use :slack, channel: :general, profile: :support  # Use a specific SlackSender profile
use :slack                                # No default channel (must pass channel: each time)
```

#### The `slack(...)` Method

The strategy adds a `slack` instance method with flexible calling conventions:

```ruby
# Positional text argument (sugar for text: kwarg)
slack "Hello world"

# Override channel
slack "Hello", channel: :other_channel

# Full kwargs
slack text: "Hello", channel: :ops_alerts, icon_emoji: "robot"

# With blocks or attachments
slack channel: :ops_alerts, blocks: [{ type: "section", text: { type: "mrkdwn", text: "*Bold*" } }]
```

### SlackSender::Notifier Base Class

For actions whose sole purpose is sending Slack notifications, inherit from `SlackSender::Notifier`:

```ruby
# app/slack_notifiers/deployments/finished.rb
module SlackNotifiers
  module Deployments
    class Finished < SlackSender::Notifier
      expects :deployment_id, type: Integer

      # Post to the deployments channel for production releases
      notify do
        channel :deployments
        only_if { production_release? }
        text { ":rocket: *Deploy finished* for `#{deployment.service}` (#{deployment.environment})" }
      end

      # Optionally also post in the incident channel if this deploy is related to an incident
      notify do
        channel :incident_channel_id
        only_if { incident_channel_id.present? }
        text { ":rocket: *Deploy finished* for `#{deployment.service}` (#{deployment.environment})" }
      end

      private

      def production_release? = deployment.environment.to_s == "production"

      # Dynamic channel ID string (e.g., "C123...") sourced from your domain model
      def incident_channel_id = deployment.incident_slack_channel_id

      def deployment = @deployment ||= Deployment.find(deployment_id)
    end
  end
end

# Call it like any Axn
SlackNotifiers::Deployments::Finished.call(deployment_id: 123)
```

#### The `notify do ... end` DSL

The `notify` block groups all Slack message configuration together, keeping it visually separated from Axn declarations like `expects`:

```ruby
notify do
  channel :notifications           # Single channel
  text { "Hello!" }                # Dynamic text (block)
end

notify do
  channels :ops_alerts, :ic        # Multiple channels
  only_if { priority == :high }    # Conditional send
  text :message_text               # Text from method
  attachments :build_attachments   # Attachments from method
end
```

**DSL Options:**

| Option | Description |
|--------|-------------|
| `channel :sym` | Single channel (symbol resolved via profile, or method if defined) |
| `channels :a, :b` | Multiple channels |
| `text { ... }` | Text content (block evaluated in instance context) |
| `text :method` | Text from method |
| `text "static"` | Static text |
| `blocks { ... }` | Slack blocks |
| `attachments { ... }` | Slack attachments |
| `icon_emoji :emoji` | Custom emoji |
| `thread_ts :method` | Thread timestamp |
| `files { ... }` | File attachments |
| `only_if { ... }` | Condition (block) — only send if truthy |
| `only_if :method` | Condition (method) — only send if truthy |
| `profile :name` | Use a specific SlackSender profile |

**Value Resolution:**

For each field, values are resolved in this order:
1. **Block**: `text { "dynamic #{value}" }` — evaluated in instance context
2. **Symbol**: `text :my_method` — calls method if it exists, otherwise treated as literal
3. **Literal**: `text "static"` — used as-is

**Required Fields:**
- At least one `channel` or `channels`
- At least one payload field (`text`, `blocks`, `attachments`, or `files`)

#### Notifier Features

Since `SlackSender::Notifier` inherits from Axn, you get:
- `expects` / `exposes` for input/output contracts
- Hooks (`before`, `after`, `on_success`, `on_failure`)
- Automatic logging and error handling
- Async execution with `call_async`

```ruby
class SlackNotifiers::DailyReport < SlackSender::Notifier
  expects :date, type: Date, default: -> { Date.current }

  notify do
    channel :reports
    text { "Daily Report for #{date.strftime('%B %d, %Y')}" }
    attachments { [{ color: "good", text: "All systems operational" }] }
  end
end

# Sync
SlackNotifiers::DailyReport.call(date: Date.yesterday)

# Async (via Sidekiq or ActiveJob)
SlackNotifiers::DailyReport.call_async(date: Date.yesterday)
```

## Configuration

### Global Configuration

Configure async backend and other global settings:

```ruby
SlackSender.configure do |config|
  # Set async backend (auto-detects Sidekiq or ActiveJob if available)
  config.async_backend = :sidekiq  # or :active_job

  # Set sandbox mode (affects sandbox channel/user_group redirects)
  # Defaults to true in non-production, false in production
  config.sandbox_mode = !Rails.env.production?

  # Set default sandbox behavior when sandbox_mode is true but profile
  # doesn't specify a sandbox.mode or sandbox.channel.replace_with
  # Options: :noop (default), :redirect, :passthrough
  config.sandbox_default_behavior = :noop

  # Enable/disable SlackSender globally
  config.enabled = true

  # Silence archived channel exceptions (default: false)
  config.silence_archived_channel_exceptions = false
end
```

### Configuration Reference

#### Global Configuration (`SlackSender.config`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `async_backend` | `Symbol` or `nil` | Auto-detected (`:sidekiq` or `:active_job` if available) | Backend for async delivery. Supported: `:sidekiq`, `:active_job` |
| `sandbox_mode` | `Boolean` or `nil` | `!Rails.env.production?` if Rails available, else `true` | Whether app is in sandbox mode (affects sandbox behavior) |
| `sandbox_default_behavior` | `Symbol` | `:noop` | Default behavior when in sandbox mode if profile doesn't specify. Options: `:noop`, `:redirect`, `:passthrough` |
| `enabled` | `Boolean` | `true` | Global enable/disable flag. When `false`, `call` and `call!` return `false` without sending |
| `silence_archived_channel_exceptions` | `Boolean` | `false` | If `true`, silently ignores `IsArchived` errors instead of reporting them |

#### Profile Configuration (`SlackSender.register`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `token` | `String` or callable | Required | Slack Bot User OAuth Token. Can be a proc/lambda for dynamic fetching |
| `default_channel` | `Symbol`, `String`, or `nil` | `nil` | Default channel to use when no channel is specified in `call`/`call!`. Can be a symbol (resolved from `channels` hash) or a channel ID string |
| `channels` | `Hash` | `{}` | Hash mapping symbol keys to channel IDs (e.g., `{ alerts: 'C123' }`) |
| `user_groups` | `Hash` | `{}` | Hash mapping symbol keys to user group IDs (e.g., `{ engineers: 'S123' }`) |
| `slack_client_config` | `Hash` | `{}` | Additional options passed to `Slack::Web::Client` constructor |
| `sandbox` | `Hash` | `{}` | Sandbox mode configuration (see below) |

#### Sandbox Configuration (`sandbox:` option)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `behavior` | `Symbol` or `nil` | Inferred (see below) | Explicit sandbox behavior: `:redirect`, `:noop`, or `:passthrough` |
| `channel.replace_with` | `String` or `nil` | `nil` | Channel ID to redirect all messages when behavior is `:redirect` |
| `channel.message_prefix` | `String` or `nil` | `":construction: _This message would have been sent to %s in production_"` | Custom prefix for sandbox channel redirects. Use `%s` placeholder for channel name |
| `user_group.replace_with` | `String` or `nil` | `nil` | User group ID to replace all group mentions when in sandbox mode |

#### Sandbox Behavior Resolution

When `config.sandbox_mode?` is true, the effective sandbox behavior is determined by:

1. **Explicit `sandbox.behavior`** — if set, use it
2. **Inferred from `sandbox.channel.replace_with`** — if present, behavior is `:redirect`
3. **Global default** — `config.sandbox_default_behavior` (defaults to `:noop`)

| Behavior | Description |
|----------|-------------|
| `:redirect` | Redirect messages to `sandbox.channel.replace_with` (required). Adds message prefix. |
| `:noop` | Don't send anything. Logs what would have been sent. Returns `false`. |
| `:passthrough` | Send to real channel (explicit opt-out of sandbox safety). |

**Note:** If `behavior: :redirect` is set but `channel.replace_with` is not provided, an `ArgumentError` is raised at profile registration.

### Exception Notifications

Exception notifications to error tracking services (e.g., Honeybadger) are handled via Axn's `on_exception` handler. Configure it separately:

```ruby
Axn.configure do |c|
  c.on_exception = proc do |e, action:, context:|
    Honeybadger.notify(e, context: { axn_context: context })
  end
end
```

See [Axn configuration documentation](https://teamshares.github.io/axn/reference/configuration#on_exception) for details.

## Sandbox Mode

When `config.sandbox_mode?` is true (default in non-production), SlackSender applies sandbox behavior based on the profile's `sandbox` configuration.

### Mode: Redirect

Redirect all messages to a sandbox channel:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: {
    production_alerts: 'C9999999999'
  },
  sandbox: {
    behavior: :redirect,  # Optional - inferred when channel.replace_with is set
    channel: {
      replace_with: 'C1234567890',
      message_prefix: '🚧 Sandbox redirect from %s'  # Optional custom prefix
    }
  }
)

# In sandbox mode, this goes to C1234567890 with a prefix
SlackSender.call(channel: :production_alerts, text: "Critical alert")
```

### Mode: Noop (Default)

Don't send anything, just log what would have been sent:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { alerts: 'C999' },
  sandbox: { behavior: :noop }
)

# In sandbox mode, this logs the message but doesn't send to Slack
SlackSender.call(channel: :alerts, text: "Test message")
# => Logs: "[SANDBOX NOOP] Profile: default | Channel: <#C999> | Text: Test message"
# => Returns false
```

If no `sandbox` config is provided, the global `config.sandbox_default_behavior` is used (defaults to `:noop`).

### Mode: Passthrough

Explicitly opt out of sandbox safety and send to real channels:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { alerts: 'C999' },
  sandbox: { behavior: :passthrough }
)

# In sandbox mode, this still sends to the real channel
SlackSender.call(channel: :alerts, text: "This goes to production!")
```

### Global Default Behavior

Set the default sandbox behavior for profiles that don't specify a behavior:

```ruby
SlackSender.configure do |config|
  config.sandbox_default_behavior = :noop  # :noop, :redirect, or :passthrough
end
```

**Note:** Setting `:redirect` as the global default will raise an error at send time if the profile doesn't have `sandbox.channel.replace_with` configured.

## Error Handling

SlackSender automatically handles common Slack API errors by logging warnings and letting Axn's exception flow handle reporting:

- **Not In Channel**: Logs warning and re-raises (non-retryable)
- **Channel Not Found**: Logs warning and re-raises (non-retryable)
- **Channel Is Archived**: Logs warning and re-raises (non-retryable). Can be silently ignored via `config.silence_archived_channel_exceptions = true`
- **Rate Limits**: Automatically retries with delay from `Retry-After` header (up to 5 retries)
- **Other Slack API Errors**: Logs warning and re-raises

For exception notifications to error tracking services (e.g., Honeybadger), configure Axn's `on_exception` handler. See [Axn configuration documentation](https://teamshares.github.io/axn/reference/configuration#on_exception) for details.

## Async Backends

### Sidekiq

If Sidekiq is available, it's automatically used:

```ruby
# No configuration needed - auto-detected
SlackSender.call(channel: :ops_alerts, text: "Message")
```

### ActiveJob

If ActiveJob is available, it can be used:

```ruby
SlackSender.configure do |config|
  config.async_backend = :active_job
end
```

### Synchronous Delivery

For synchronous delivery (no background job):

```ruby
# Returns thread timestamp immediately
thread_ts = SlackSender.call!(
  channel: :ops_alerts,
  text: "Message"
)
```

**Note**: Synchronous delivery doesn't include automatic retries for rate limits.

## Rate Limiting & Retries

When using async delivery, SlackSender automatically:

- Detects rate limit errors from Slack API responses
- Extracts `Retry-After` header value
- Schedules retry with appropriate delay
- Retries up to 5 times before giving up

Rate limit handling works with both Sidekiq and ActiveJob backends.

The following errors are not retried (discarded immediately):
- `NotInChannel` - Bot not in channel
- `ChannelNotFound` - Channel doesn't exist
- `IsArchived` - Channel is archived (unless `silence_archived_channel_exceptions` is true)

## Examples

### Example 1: Deployment Notifications

```ruby
SlackSender.call(
  channel: :deployments,
  text: ":rocket: Deploy finished for `my-app` (#{Rails.env})",
  blocks: [
    {
      type: "section",
      fields: [
        { type: "mrkdwn", text: "*Environment:*\n#{Rails.env}" },
        { type: "mrkdwn", text: "*Version:*\n#{ENV['APP_VERSION']}" }
      ]
    }
  ]
)
```

### Example 2: Error Alerts

```ruby
SlackSender.call(
  channel: :ops_alerts,
  text: ":rotating_light: Payment processing error",
  attachments: [
    {
      color: "danger",
      fields: [
        { title: "Error", value: error.message, short: false },
        { title: "User", value: user.email, short: true }
      ]
    }
  ]
)
```

### Example 3: Scheduled Reports with File Upload

```ruby
# Generate and send report (synchronous for file upload)
report = generate_daily_report
thread_ts = SlackSender.call!(
  channel: :reports,
  text: "Daily Report - #{Date.today}",
  files: [report.to_file]
)

# Follow up in thread
SlackSender.call(
  channel: :reports,
  text: "Summary: no SEV incidents; deploys are healthy",
  thread_ts: thread_ts
)
```

## Troubleshooting / FAQ

### Q: Why aren't my messages being sent?

A: Check the following:
1. Ensure `SlackSender.config.enabled` is `true` (default)
2. Verify your profile is registered: `SlackSender.profile(:default)`
3. Check that an async backend is available if using `call` (not `call!`)
4. Verify your Slack token is valid and has the required scopes

### Q: Messages work in production but not in development

A: If sandbox channel is configured, all messages are redirected there when in sandbox mode. Check:
1. `SlackSender.config.sandbox_mode?` - should be `true` in development
2. Your `sandbox.channel.replace_with` channel ID is correct
3. The bot is invited to the sandbox channel

### Q: Getting "NotInChannel" errors

A: The bot must be invited to the channel. Options:
1. Invite the bot to the channel manually
2. See: https://stackoverflow.com/a/68475477

### Q: File uploads fail with async delivery

A: File uploads are only supported with synchronous delivery (`call!`). This is a known limitation and will be addressed in a future release. Use `call!` for file uploads:

```ruby
SlackSender.call!(channel: :ops_alerts, files: [file])
```

### Q: How do I disable SlackSender temporarily?

A: Set `SlackSender.config.enabled = false`. All `call` and `call!` methods will return `false` without sending messages.

### Q: Can I use multiple Slack workspaces?

A: Yes, register multiple profiles:

```ruby
SlackSender.register(:workspace1, token: TOKEN1, channels: {...})
SlackSender.register(:workspace2, token: TOKEN2, channels: {...})

SlackSender.profile(:workspace1).call(...)
SlackSender.profile(:workspace2).call(...)
```

### Q: How are rate limits handled?

A: SlackSender automatically detects rate limit errors and retries with the delay specified in Slack's `Retry-After` header. Retries happen up to 5 times before giving up.

## Compatibility

- **Ruby**: >= 3.2.1 (uses endless methods from Ruby 3.0+ and literal value omission from 3.1+)
- **Dependencies**:
  - `axn` (0.1.0-alpha.3)
  - `slack-ruby-client` (latest)
- **Optional dependencies**:
  - `sidekiq` (for async delivery)
  - `active_job` (for async delivery)
  - `active_storage` (for ActiveStorage::Attachment file support)

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Running Tests

```bash
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at `https://github.com/teamshares/slack_sender`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
