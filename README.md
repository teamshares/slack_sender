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
  dev_channel: 'C1234567890',  # Optional: redirect all messages here in non-production
  dev_user_group: 'S_DEV_GROUP',  # Optional: replace all group mentions here in non-production
  error_channel: 'C0987654321', # Optional: receive error notifications here
  channels: {
    alerts: 'C1111111111',
    general: 'C2222222222',
  },
  user_groups: {
    engineers: 'S1234567890',
  }
)
```

### 2. Send Messages

```ruby
# Async delivery (recommended) - uses Sidekiq or ActiveJob
SlackSender.call(
  channel: :alerts,
  text: "Server is running low on memory"
)

# Synchronous delivery (returns thread timestamp)
thread_ts = SlackSender.call!(
  channel: :alerts,
  text: "Deployment completed successfully"
)
```

## Usage

### Basic Messages

```ruby
# Simple text message
SlackSender.call(
  channel: :alerts,
  text: "Hello, World!"
)

# With markdown formatting
SlackSender.call(
  channel: :alerts,
  text: "User *#{user.name}* just signed up"
)
```

### Channel Resolution

Channels can be specified as symbols (resolved from profile config) or channel IDs:

```ruby
# Using symbol (resolved from channels hash)
SlackSender.call(channel: :alerts, text: "Alert")

# Using channel ID directly
SlackSender.call(channel: "C1234567890", text: "Alert")
```

### Rich Messages

```ruby
# With blocks
SlackSender.call(
  channel: :alerts,
  blocks: [
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "New deployment to production"
      }
    }
  ]
)

# With attachments
SlackSender.call(
  channel: :alerts,
  attachments: [
    {
      color: "good",
      text: "Deployment successful"
    }
  ]
)

# With custom emoji
SlackSender.call(
  channel: :alerts,
  text: "Robot says hello",
  icon_emoji: "robot"
)
```

### File Uploads

File uploads are supported with synchronous delivery (`call!`). Note: file uploads are not yet supported with async delivery (feature planned post alpha release).

```ruby
# Single file
SlackSender.call!(
  channel: :alerts,
  text: "Here's the report",
  files: [File.open("report.pdf")]
)

# Multiple files
SlackSender.call!(
  channel: :alerts,
  text: "Multiple files attached",
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
  channel: :alerts,
  text: "This is a reply",
  thread_ts: "1234567890.123456"
)

# Get thread timestamp from initial message
thread_ts = SlackSender.call!(
  channel: :alerts,
  text: "Initial message"
)
# thread_ts => "1234567890.123456"
```

### User Group Mentions

Format user group mentions (automatically redirects to `dev_user_group` in non-production):

```ruby
SlackSender.format_group_mention(:engineers)
# => "<!subteam^S1234567890|@engineers>"
```

If `dev_user_group` is configured and the app is not in production (per `config.in_production?`), `format_group_mention` will replace the requested group with the `dev_user_group` instead, similar to how `dev_channel` redirects channel messages:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_user_group: 'S_DEV_GROUP',  # All group mentions use this in dev
  user_groups: {
    engineers: 'S1234567890',  # Would be replaced with dev_user_group in non-production
  }
)

# In development, this returns the dev_user_group mention
SlackSender.format_group_mention(:engineers)
# => "<!subteam^S_DEV_GROUP>"
```

### Dynamic Token

Use a callable for the token to fetch it dynamically:

```ruby
SlackSender.register(
  token: -> { SecretsManager.get_slack_token },
  channels: { alerts: 'C123' }
)
```

The token is memoized after first access, so the callable is only evaluated once per profile instance.

### Multiple Profiles

Register multiple profiles for different Slack workspaces:

```ruby
# Default profile
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { alerts: 'C123' }
)

# Customer support workspace
SlackSender.register(:support,
  token: ENV['SUPPORT_SLACK_TOKEN'],
  channels: { tickets: 'C456' }
)

# Use specific profile
SlackSender.profile(:support).call(
  channel: :tickets,
  text: "New ticket received"
)

# Or use bracket notation
SlackSender[:support].call(
  channel: :tickets,
  text: "New ticket received"
)

# Or override default profile with profile parameter
SlackSender.call(
  profile: :support,
  channel: :tickets,
  text: "New ticket received"
)
```

## Configuration

### Global Configuration

Configure async backend and other global settings:

```ruby
SlackSender.configure do |config|
  # Set async backend (auto-detects Sidekiq or ActiveJob if available)
  config.async_backend = :sidekiq  # or :active_job

  # Set production mode (affects dev channel redirects)
  config.in_production = Rails.env.production?

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
| `in_production` | `Boolean` or `nil` | `Rails.env.production?` if Rails available, else `false` | Whether app is in production (affects dev channel redirects) |
| `enabled` | `Boolean` | `true` | Global enable/disable flag. When `false`, `call` and `call!` return `false` without sending |
| `silence_archived_channel_exceptions` | `Boolean` | `false` | If `true`, silently ignores `IsArchived` errors instead of reporting them |

#### Profile Configuration (`SlackSender.register`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `token` | `String` or callable | Required | Slack Bot User OAuth Token. Can be a proc/lambda for dynamic fetching |
| `dev_channel` | `String` or `nil` | `nil` | Channel ID to redirect all messages in non-production |
| `dev_user_group` | `String` or `nil` | `nil` | User group ID to replace all group mentions in non-production |
| `error_channel` | `String` or `nil` | `nil` | Channel ID for configuration-related error notifications (NotInChannel, ChannelNotFound, IsArchived). Can be unset to avoid duplicate alerts (warnings will be logged instead) |
| `channels` | `Hash` | `{}` | Hash mapping symbol keys to channel IDs (e.g., `{ alerts: 'C123' }`) |
| `user_groups` | `Hash` | `{}` | Hash mapping symbol keys to user group IDs (e.g., `{ engineers: 'S123' }`) |
| `slack_client_config` | `Hash` | `{}` | Additional options passed to `Slack::Web::Client` constructor |
| `dev_channel_redirect_prefix` | `String` or `nil` | `":construction: _This message would have been sent to %s in production_"` | Custom prefix for dev channel redirects. Use `%s` placeholder for channel name |

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

## Development Mode

In non-production environments, messages are automatically redirected to the `dev_channel` if configured:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_channel: 'C1234567890',  # All messages go here in dev
  channels: {
    production_alerts: 'C9999999999'  # Would redirect to dev_channel
  }
)

# In development, this goes to dev_channel with a prefix
SlackSender.call(
  channel: :production_alerts,
  text: "Critical alert"
)
# => Sent to C1234567890 with prefix: "This message would have been sent to #production_alerts in production"
```

Customize the redirect prefix:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_channel: 'C1234567890',
  dev_channel_redirect_prefix: "🚧 Dev redirect: %s",
  channels: { alerts: 'C999' }
)
```

## Error Handling

SlackSender automatically handles common Slack API errors:

- **Not In Channel**: Sends error notification to `error_channel` (if configured), otherwise logs warning
- **Channel Not Found**: Sends error notification to `error_channel` (if configured), otherwise logs warning
- **Channel Is Archived**: Sends error notification to `error_channel` (if configured and `silence_archived_channel_exceptions` is false/nil), otherwise logs warning. Can be ignored via `config.silence_archived_channel_exceptions = true`
- **Rate Limits**: Automatically retries with delay from `Retry-After` header (up to 5 retries)
- **Other Errors**: Authentication and authorization errors (invalid_auth, token_revoked, missing_scope, etc.) log warnings but don't attempt Slack delivery (since they would fail)

For exception notifications to error tracking services (e.g., Honeybadger), configure Axn's `on_exception` handler. See [Axn configuration documentation](https://teamshares.github.io/axn/reference/configuration#on_exception) for details.

## Async Backends

### Sidekiq

If Sidekiq is available, it's automatically used:

```ruby
# No configuration needed - auto-detected
SlackSender.call(channel: :alerts, text: "Message")
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
  channel: :alerts,
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
  text: "Deployment to #{Rails.env} completed",
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
  channel: :errors,
  text: "Error in payment processing",
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
  text: "Report analysis complete",
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

A: If `dev_channel` is configured, all messages are redirected there in non-production. Check:
1. `SlackSender.config.in_production?` - should be `false` in development
2. Your `dev_channel` channel ID is correct
3. The bot is invited to the `dev_channel`

### Q: Getting "NotInChannel" errors

A: The bot must be invited to the channel. Options:
1. Invite the bot to the channel manually
2. Configure `error_channel` to receive notifications about this error
3. See: https://stackoverflow.com/a/68475477

### Q: File uploads fail with async delivery

A: File uploads are only supported with synchronous delivery (`call!`). This is a known limitation and will be addressed in a future release. Use `call!` for file uploads:

```ruby
SlackSender.call!(channel: :alerts, files: [file])
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

Bug reports and pull requests are welcome on GitHub at https://github.com/teamshares/slack_sender.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
