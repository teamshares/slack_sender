# Slacker -- Slack messaging: lazy at call time, diligent at delivery time

Background dispatch with automatic rate-limit retries.

Slacker provides a simple, reliable way to send Slack messages from Ruby applications. It handles rate limiting, retries, error notifications, and development environment redirects automatically.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slacker-rb'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install slacker-rb
```

## Requirements

- Ruby >= 3.2.1
- A Slack API token (Bot User OAuth Token)
- For async delivery: Sidekiq or ActiveJob

## Quick Start

### 1. Configure a Profile

Register a profile with your Slack token and channel configuration:

```ruby
Slacker.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_channel: 'C1234567890',  # Optional: redirect all messages here in non-production
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
Slacker.call(
  channel: :alerts,
  text: "Server is running low on memory"
)

# Synchronous delivery (returns thread timestamp)
thread_ts = Slacker.call!(
  channel: :alerts,
  text: "Deployment completed successfully"
)
```

## Configuration

### Global Configuration

Configure async backend and other global settings:

```ruby
Slacker.configure do |config|
  # Set async backend (auto-detects Sidekiq or ActiveJob if available)
  config.async_backend = :sidekiq  # or :active_job

  # Set production mode (affects dev channel redirects)
  config.in_production = Rails.env.production?

  # Limit file size for background jobs (prevents Redis overload)
  config.max_background_file_size = 10.megabytes

  # Custom error notifier (called when Slack errors occur)
  config.error_notifier = ->(error, context) do
    Honeybadger.notify(error, context: context)
  end
end
```

### Multiple Profiles

Register multiple profiles for different Slack workspaces:

```ruby
# Default profile
Slacker.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { alerts: 'C123' }
)

# Customer support workspace
Slacker.register(:support,
  token: ENV['SUPPORT_SLACK_TOKEN'],
  channels: { tickets: 'C456' }
)

# Use specific profile
Slacker.profile(:support).call(
  channel: :tickets,
  text: "New ticket received"
)
```

### Profile Options

- `token` - Slack Bot User OAuth Token (string or callable)
- `dev_channel` - Channel ID to redirect all messages in non-production
- `error_channel` - Channel ID for error notifications
- `channels` - Hash mapping symbol keys to channel IDs
- `user_groups` - Hash mapping symbol keys to user group IDs
- `slack_client_config` - Additional options passed to `Slack::Web::Client`
- `dev_channel_redirect_prefix` - Custom prefix for dev channel redirects

## Usage

### Basic Messages

```ruby
# Simple text message
Slacker.call(
  channel: :alerts,
  text: "Hello, World!"
)

# With markdown formatting
Slacker.call(
  channel: :alerts,
  text: "User *#{user.name}* just signed up"
)
```

### Channel Resolution

Channels can be specified as symbols (resolved from profile config) or channel IDs:

```ruby
# Using symbol (resolved from channels hash)
Slacker.call(channel: :alerts, text: "Alert")

# Using channel ID directly
Slacker.call(channel: "C1234567890", text: "Alert")
```

### Rich Messages

```ruby
# With blocks
Slacker.call(
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
Slacker.call(
  channel: :alerts,
  attachments: [
    {
      color: "good",
      text: "Deployment successful"
    }
  ]
)

# With custom emoji
Slacker.call(
  channel: :alerts,
  text: "Robot says hello",
  icon_emoji: "robot"
)
```

### File Uploads

```ruby
# Single file
Slacker.call(
  channel: :alerts,
  text: "Here's the report",
  files: [File.open("report.pdf")]
)

# Multiple files
Slacker.call(
  channel: :alerts,
  text: "Multiple files attached",
  files: [
    File.open("report.pdf"),
    File.open("data.csv")
  ]
)

# File with metadata
Slacker.call(
  channel: :alerts,
  files: [{
    file: File.open("report.pdf"),
    filename: "monthly-report.pdf",
    title: "Monthly Report"
  }]
)
```

### Threading

```ruby
# Reply to a thread
Slacker.call(
  channel: :alerts,
  text: "This is a reply",
  thread_ts: "1234567890.123456"
)

# Get thread timestamp from initial message
thread_ts = Slacker.call!(
  channel: :alerts,
  text: "Initial message"
)
# thread_ts => "1234567890.123456"
```

### User Group Mentions

```ruby
# Format user group mention (automatically redirects to dev group in non-production)
Slacker.format_group_mention(:engineers)
# => "<!subteam^S1234567890|@engineers>"
```

### Dynamic Token

Use a callable for the token to fetch it dynamically:

```ruby
Slacker.register(
  token: -> { SecretsManager.get_slack_token },
  channels: { alerts: 'C123' }
)
```

## Development Mode

In non-production environments, messages are automatically redirected to the `dev_channel` if configured:

```ruby
Slacker.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_channel: 'C1234567890',  # All messages go here in dev
  channels: {
    production_alerts: 'C9999999999'  # Would redirect to dev_channel
  }
)

# In development, this goes to dev_channel with a prefix
Slacker.call(
  channel: :production_alerts,
  text: "Critical alert"
)
# => Sent to C1234567890 with prefix: "This message would have been sent to #production_alerts in production"
```

Customize the redirect prefix:

```ruby
Slacker.register(
  token: ENV['SLACK_BOT_TOKEN'],
  dev_channel: 'C1234567890',
  dev_channel_redirect_prefix: "🚧 Dev redirect: %s",
  channels: { alerts: 'C999' }
)
```

## Error Handling

Slacker automatically handles common Slack API errors:

- **Not In Channel**: Sends error notification to `error_channel` (if configured)
- **Channel Not Found**: Sends error notification to `error_channel` (if configured)
- **Rate Limits**: Automatically retries with delay from `Retry-After` header

Errors are logged or sent to your configured `error_notifier` if the error channel is unavailable.

## Async Backends

### Sidekiq

If Sidekiq is available, it's automatically used:

```ruby
# No configuration needed - auto-detected
Slacker.call(channel: :alerts, text: "Message")
```

### ActiveJob

If ActiveJob is available, it can be used:

```ruby
Slacker.configure do |config|
  config.async_backend = :active_job
end
```

### Synchronous Delivery

For synchronous delivery (no background job):

```ruby
# Returns thread timestamp immediately
thread_ts = Slacker.call!(
  channel: :alerts,
  text: "Message"
)
```

**Note**: Synchronous delivery doesn't include automatic retries for rate limits.

## Rate Limiting & Retries

When using async delivery, Slacker automatically:

- Detects rate limit errors from Slack API responses
- Extracts `Retry-After` header value
- Schedules retry with appropriate delay
- Retries up to 5 times before giving up

Rate limit handling works with both Sidekiq and ActiveJob backends.

## File Size Limits

To prevent large files from overloading your job queue, set a maximum file size:

```ruby
Slacker.configure do |config|
  config.max_background_file_size = 10.megabytes
end

# This will raise an error if total file size exceeds limit
Slacker.call(
  channel: :alerts,
  files: [large_file]  # Raises if > 10MB
)
```

## Examples

### Deployment Notifications

```ruby
Slacker.call(
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

### Error Alerts

```ruby
Slacker.call(
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

### Scheduled Reports

```ruby
# Generate and send report
report = generate_daily_report
Slacker.call(
  channel: :reports,
  text: "Daily Report - #{Date.today}",
  files: [report.to_file]
)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/teamshares/slacker-rb.
