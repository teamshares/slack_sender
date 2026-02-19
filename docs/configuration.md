# Configuration

[← Back to README](../README.md)

This guide covers global configuration, profile registration, and sandbox mode settings.

## Global Configuration

Configure SlackSender behavior via `SlackSender.configure` (e.g. in a Rails initializer):

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

  # Enable/disable SlackSender globally (default: true)
  config.enabled = ENV["DISABLE_SLACK"] != "1"

  # Silence archived channel exceptions (default: false)
  config.silence_archived_channel_exceptions = false

  # Control autoloading namespace for app/slack_notifiers (default: true)
  # When true:  app/slack_notifiers/foo.rb -> SlackNotifiers::Foo
  # When false: app/slack_notifiers/foo.rb -> Foo (standard Rails behavior)
  config.use_slack_notifiers_namespace = true
end
```

### Global Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `async_backend` | `Symbol` or `nil` | Auto-detected | Backend for async delivery. Supported: `:sidekiq`, `:active_job` |
| `sandbox_mode` | `Boolean` or `nil` | `!Rails.env.production?` if Rails available, else `true` | Whether app is in sandbox mode |
| `sandbox_default_behavior` | `Symbol` | `:noop` | Default behavior when in sandbox mode if profile doesn't specify. Options: `:noop`, `:redirect`, `:passthrough` |
| `enabled` | `Boolean` | `true` | Global enable/disable flag. When `false`, `call` and `call!` return `false` without sending |
| `silence_archived_channel_exceptions` | `Boolean` | `false` | If `true`, silently ignores `IsArchived` errors instead of reporting them |
| `max_inline_file_size` | `Integer` | `524_288` (512 KB) | Max total file size to serialize directly to job payload |
| `max_async_file_upload_size` | `Integer` or `nil` | `26_214_400` (25 MB) | Max total file size for async uploads. Set to `nil` to disable |
| `use_slack_notifiers_namespace` | `Boolean` | `true` | When `true`, files in `app/slack_notifiers` are autoloaded under the `SlackNotifiers` namespace |

---

## Profile Registration

A **profile** represents a Slack workspace configuration. Register profiles with `SlackSender.register`:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  default_channel: :ops_alerts,
  channels: {
    ops_alerts: 'C1111111111',
    deployments: 'C2222222222',
    reports: 'C3333333333',
  },
  user_groups: {
    engineers: 'S1234567890',
  },
  sandbox: {
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

### Profile Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `token` | `String` or callable | Required | Slack Bot User OAuth Token. Can be a proc/lambda for dynamic fetching |
| `default_channel` | `Symbol`, `String`, or `nil` | `nil` | Default channel when none is specified in `call`/`call!` |
| `channels` | `Hash` | `{}` | Hash mapping symbol keys to channel IDs (e.g., `{ alerts: 'C123' }`) |
| `user_groups` | `Hash` | `{}` | Hash mapping symbol keys to user group IDs (e.g., `{ engineers: 'S123' }`) |
| `slack_client_config` | `Hash` | `{}` | Additional options passed to `Slack::Web::Client` constructor |
| `sandbox` | `Hash` | `{}` | Sandbox mode configuration (see below) |

### Dynamic Token

Use a callable for the token to fetch it dynamically:

```ruby
SlackSender.register(
  token: -> { SecretsManager.get_slack_token },
  channels: { ops_alerts: 'C123' }
)
```

The token is memoized after first access.

### Multiple Profiles

Register multiple profiles for different Slack workspaces:

```ruby
# Internal engineering workspace (default profile)
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
SlackSender[:support].call(channel: :support_tickets, text: "...")

# Or override default profile with profile parameter
SlackSender.call(profile: :support, channel: :support_tickets, text: "...")
```

---

## Sandbox Mode

When `config.sandbox_mode?` is true (default in non-production), SlackSender applies sandbox behavior based on the profile's `sandbox` configuration.

### Sandbox Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `behavior` | `Symbol` or `nil` | Inferred | Explicit sandbox behavior: `:redirect`, `:noop`, or `:passthrough` |
| `channel.replace_with` | `String` or `nil` | `nil` | Channel ID to redirect all messages when behavior is `:redirect` |
| `channel.message_prefix` | `String` or `nil` | See below | Custom prefix for sandbox channel redirects. Use `%s` placeholder for channel name |
| `user_group.replace_with` | `String` or `nil` | `nil` | User group ID to replace all group mentions when in sandbox mode |

Default message prefix: `:construction: _This message would have been sent to %s in production_`

### Behavior Resolution

When `config.sandbox_mode?` is true, the effective sandbox behavior is determined by:

1. **Explicit `sandbox.behavior`** — if set, use it
2. **Inferred from `sandbox.channel.replace_with`** — if present, behavior is `:redirect`
3. **Global default** — `config.sandbox_default_behavior` (defaults to `:noop`)

| Behavior | Description |
|----------|-------------|
| `:redirect` | Redirect messages to `sandbox.channel.replace_with` (required). Adds message prefix. |
| `:noop` | Don't send anything. Logs what would have been sent. Returns `false`. |
| `:passthrough` | Send to real channel (explicit opt-out of sandbox safety). |

### Mode: Redirect

Redirect all messages to a sandbox channel:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  channels: { production_alerts: 'C9999999999' },
  sandbox: {
    behavior: :redirect,  # Optional - inferred when channel.replace_with is set
    channel: {
      replace_with: 'C1234567890',
      message_prefix: ':test_tube: Sandbox redirect from %s'
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

---

## Required Slack Scopes

Your Slack app needs specific OAuth scopes depending on which features you use. Add these under **OAuth & Permissions** → **Bot Token Scopes** in your [Slack app settings](https://api.slack.com/apps).

**Minimum scopes for basic messaging:**
- `chat:write`

**Recommended scopes for full functionality:**

| Scope | Required For | Notes |
|-------|--------------|-------|
| `chat:write` | All messaging | Required for `chat.postMessage` |
| `chat:write.public` | Public channels | Post to public channels your bot hasn't been added to |
| `files:write` | File uploads | Required for `files.getUploadURLExternal` and `files.completeUploadExternal` |
| `files:read` | File metadata | Required if you need thread timestamps from file uploads |

After adding scopes, reinstall the app to your workspace to apply the changes.

---

## Exception Notifications

Exception notifications to error tracking services (e.g., Honeybadger) are handled via Axn's `on_exception` handler:

```ruby
Axn.configure do |c|
  c.on_exception = proc do |e, action:, context:|
    Honeybadger.notify(e, context: { axn_context: context })
  end
end
```

See [Axn configuration documentation](https://teamshares.github.io/axn/reference/configuration#on_exception) for details.
