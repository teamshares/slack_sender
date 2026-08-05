# Usage Guide

[← Back to README](../README.md)

This guide covers sending messages, file uploads, threading, and advanced delivery patterns.

## Basic Messages

```ruby
# Simple text message
SlackSender.call(
  channel: :ops_alerts,
  text: ":warning: Redis latency is *elevated*"
)
```

Text is parsed as [Slack mrkdwn](https://api.slack.com/reference/surfaces/formatting) by default.

### Sync vs Async Delivery

| Method | Delivery | Return Value | Use When |
|--------|----------|--------------|----------|
| `call(...)` | Async (background job) | `true` or `false` | Default; enables auto-retry for rate limits |
| `call!(...)` | Sync (immediate) | Thread timestamp or `false` | You need the `thread_ts` return value |

```ruby
# Async delivery (recommended) - uses Sidekiq or ActiveJob
SlackSender.call(channel: :ops_alerts, text: "Alert")

# Synchronous delivery (returns thread timestamp)
thread_ts = SlackSender.call!(channel: :deployments, text: "Deploy finished")
```

**Note:** If `text:` is explicitly provided but blank (and you did not provide `blocks`, `attachments`, or `files`), SlackSender treats it as a no-op and returns `false`.

---

## Channel Resolution

Channels can be specified as symbols (resolved from profile config) or channel IDs:

```ruby
# Using symbol (resolved from channels hash)
SlackSender.call(channel: :ops_alerts, text: "Alert")

# Using channel ID directly
SlackSender.call(channel: "C1234567890", text: "Alert")
```

### Default Channel

Configure a default channel for a profile to avoid passing `channel:` on every call:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  default_channel: :ops_alerts,
  channels: {
    ops_alerts: 'C1111111111',
    deployments: 'C2222222222',
  }
)

# These are equivalent:
SlackSender.call(text: "Alert!")                       # Uses default_channel
SlackSender.call(channel: :ops_alerts, text: "Alert!") # Explicit channel
```

### Sandbox Mode

To prevent accidental notifications in development or staging environments, you can enable sandbox mode. When active, all messages—regardless of their target channel—are redirected to a single "sandbox" channel. This ensures you can test notifications safely without spamming real users.

#### Per-action sandbox override

Sandbox mode is normally global (derived from `Rails.env`, or set via `SlackSender.config.sandbox_mode = …`). An individual Axn action that uses the `:slack` strategy can override it for its own sends via the axn `configure(:slack_sender)` DSL — useful when one action must always deliver (or always be sandboxed) regardless of the global setting:

```ruby
class CriticalPageNotifier
  include Axn
  use :slack, channel: :on_call

  # Always deliver, even in a sandboxed (non-production) environment.
  configure(:slack_sender) { |c| c.sandbox_mode = false }

  def call = slack!("Pager fired 🔥")
end
```

The override is resolved when the action sends and inherits into subclasses (a subclass can set its own). Actions that don't declare one are unaffected and follow the global config as before. It applies to the `:slack` strategy delivery path only, not the standalone `SlackSender.group_link` helper.

---

## Rich Messages

SlackSender passes blocks, attachments, and icon_emoji through [directly to slack-ruby-client](https://www.rubydoc.info/gems/slack-ruby-client/Slack/Web/Api/Endpoints/Chat#chat_postMessage-instance_method).


### Blocks

```ruby
SlackSender.call(
  channel: :deployments,
  blocks: [
    {
      type: "section",
      text: { type: "mrkdwn", text: ":rocket: *Deploy finished* for `my-app`" }
    }
  ]
)
```

### Attachments


```ruby
SlackSender.call(
  channel: :ops_alerts,
  attachments: [
    {
      color: "good",
      text: "Autoscaling event completed successfully"
    }
  ]
)
```

### Custom Emoji


```ruby
SlackSender.call(
  channel: :ops_alerts,
  text: "Background job queue is healthy",
  icon_emoji: "robot"
)
```

### Other `chat.postMessage` Options

First-class options (`text`, `blocks`, `attachments`, `icon_emoji`, `thread_ts`) cover the common cases. For anything else the [`chat.postMessage` endpoint](https://www.rubydoc.info/gems/slack-ruby-client/Slack/Web/Api/Endpoints/Chat#chat_postMessage-instance_method) supports — `unfurl_links`, `unfurl_media`, `reply_broadcast`, `metadata`, etc. — pass a `slack_options:` hash. It is forwarded straight through to Slack:

```ruby
SlackSender.call(
  channel: :ops_alerts,
  text: "https://example.com/runbook",
  slack_options: { unfurl_links: false, unfurl_media: false }
)
```

The managed keys above always take precedence over `slack_options`, so sandbox channel redirection and text formatting can't be accidentally overridden. `slack_options:` applies to text messages only — it is not forwarded on the file-upload path (a different Slack endpoint).

---

## File Uploads

File uploads are supported with both synchronous (`call!`) and async (`call`) delivery.

```ruby
# Single file - use file: (singular)
SlackSender.call!(
  channel: :reports,
  text: "Daily ops report attached",
  file: File.open("report.pdf")
)

# Multiple files - use files: (plural)
SlackSender.call!(
  channel: :reports,
  text: "Daily ops report (details + raw export)",
  files: [
    File.open("report.pdf"),
    File.open("data.csv")
  ]
)

# Async delivery (background job handles sharing)
SlackSender.call(
  channel: :alerts,
  text: "Multiple files attached",
  files: [File.open("report.pdf"), File.open("data.csv")]
)
```

### ⚠️ Channel ID Required

Unlike normal message sending, Slack's `files_upload_v2` API requires channel _IDs_ (e.g., `C024BE91L`, `D032AC32T`) and does _not_ support usernames or channel names:

```ruby
# Works - using channel ID from profile
SlackSender.call!(channel: :alerts, file: file)

# Works - using channel ID directly
SlackSender.call!(channel: "C024BE91L", file: file)

# Fails - @username not supported for file uploads
SlackSender.call!(channel: "@username", file: file)

# Fails - #channel-name not supported for file uploads
SlackSender.call!(channel: "#general", file: file)
```

To send files as a DM, use the DM channel ID (starts with `D`) from Slack's URL.

### Async File Upload Behavior

Files are uploaded to Slack's servers synchronously before the background job is enqueued. The job then shares the uploaded files to the channel. This means `call` with files may block briefly during the upload phase.

### Size Limits

- Individual files cannot exceed **1 GB** (Slack's hard limit)
- Total file size for async uploads is limited by `max_async_file_upload_size` (default 25 MB)
- Use `call!` for synchronous upload when you need to upload files larger than `max_async_file_upload_size`

### Supported File Types

- `File` objects
- `Tempfile` objects
- `StringIO` objects
- `ActiveStorage::Attachment` objects (if ActiveStorage is available)
- String file paths (will be opened automatically)
- Any object that responds to `read` and has `original_filename` or `path`

---

## Threading

```ruby
# Get thread timestamp from initial message
thread_ts = SlackSender.call!(
  channel: :ops_alerts,
  text: ":rotating_light: Elevated 500s detected on /checkout"
)
# thread_ts => "1234567890.123456"

# Reply to a thread
SlackSender.call(
  channel: :ops_alerts,
  text: "Mitigation: rolled back to previous release",
  thread_ts: thread_ts
)
```

---

## Multi-Channel Delivery

Send the same message to multiple channels with a single call using `channels:` (plural):

```ruby
# Async delivery to multiple channels
SlackSender.call(
  channels: [:ops_alerts, :deployments],
  text: ":rocket: Deploy finished for my-app"
)
```

**Key behaviors:**
- Multi-channel delivery is only supported via async (`call`). Using `call!` with `channels:` raises an error (due to complexity in handling partial failures)
- Files are uploaded once and shared to all channels efficiently
- Each channel receives a separate background job with independent retry handling
- Single-element arrays (e.g., `channels: [:ops_alerts]`) are normalized to `channel:`

```ruby
# Sync multi-channel not supported
SlackSender.call!(channels: [:a, :b], text: "...")  # Raises ArgumentError

# Use async instead
SlackSender.call(channels: [:a, :b], text: "...")

# Or send individually if you need sync (but beware :b may fail with e.g. a ratelimit error after :a has already been delivered)
[:a, :b].each { |ch| SlackSender.call!(channel: ch, text: "...") }
```

---

## User Group Mentions

Format user group mentions with `SlackSender.group_link`. This is sandbox-aware and supports symbol keys from your profile's `user_groups` registry:

```ruby
SlackSender.group_link(:on_call)
# => "<!subteam^S1234567890>"
```

`group_link` is defined **per profile** — `SlackSender.group_link(...)` is just a convenience that delegates to the default profile. Each profile resolves symbol keys against *its own* `user_groups` registry, so you can format a mention for any registered profile:

```ruby
SlackSender[:health_insurance].group_link(:benefits_team)
# => resolves :benefits_team from the :health_insurance profile's user_groups
```

Passing a string is treated as a raw group ID (no registry lookup), on any profile.

If `sandbox.user_group.replace_with` is configured and the app is in sandbox mode, `group_link` will replace the requested group with the sandbox user_group instead:

```ruby
SlackSender.register(
  token: ENV['SLACK_BOT_TOKEN'],
  user_groups: { engineers: 'S1234567890' },
  sandbox: {
    user_group: { replace_with: 'S_DEV_GROUP' }
  }
)

# In sandbox mode, this returns the sandbox user_group mention
SlackSender.group_link(:engineers)
# => "<!subteam^S_DEV_GROUP>"
```

### Other Formatting Helpers

For user mentions, channels, links, and other formatting, use the `Slack::Messages::Formatting` helpers provided by the underlying [slack-ruby-client](https://github.com/slack-ruby/slack-ruby-client#message-formatting):

```ruby
SlackSender.call(
  channel: :ops_alerts,
  text: [
    ":rotating_light: Incident acknowledged by #{Slack::Messages::Formatting.user_link(user.slack_id)}",
    Slack::Messages::Formatting.url_link('Incident timeline', 'https://status.example.com/incidents/123'),
  ].join("\n")
)
```

---

## Rate Limiting & Retries

When using async delivery, SlackSender automatically:

- Detects rate limit errors from Slack API responses
- Extracts `Retry-After` header value
- Schedules retry with appropriate delay (+ jitter)
- Retries up to 5 times before giving up

Rate limit handling works with both Sidekiq and ActiveJob backends.

---

## Error Handling

The following errors will log warning but are _not_ retried (discarded immediately):
- `NotInChannel` - Bot not in channel
- `ChannelNotFound` - Channel doesn't exist
- `IsArchived` - Channel is archived (NOTE: skips warning if `config.silence_archived_channel_exceptions = true`)

Other Slack API errors will be re-raised (so will retry if sent via background processor).

---

## Examples

### Deployment Notifications

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

### Error Alerts

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

### Scheduled Reports with File Upload

```ruby
# Generate and send report (synchronous for thread_ts)
report = generate_daily_report
thread_ts = SlackSender.call!(
  channel: :reports,
  text: "Daily Report - #{Date.today}",
  file: report.to_file
)

# Follow up in thread
SlackSender.call(
  channel: :reports,
  text: "Summary: no SEV incidents; deploys are healthy",
  thread_ts: thread_ts
)
```

### Dedicated Notifiers

For complex notifications, you can simplify your code by creating dedicated notifier classes using `SlackSender::Notifier`. This allows you to encapsulate logic, use callbacks, and keep your business logic clean.  See documentation on [SlackSender::Notifier Base Class](axn_integration.md#slacksendernotifier-base-class) for details.

```ruby
class DeployNotifier < SlackSender::Notifier
  expects :service_name

  notify do
    channel :deployments
    text { ":rocket: #{service_name} deployed successfully!" }
  end
end

# Usage
DeployNotifier.call(service_name: "payment-service")
```
