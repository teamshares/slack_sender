# Troubleshooting & FAQ

[← Back to README](../README.md)

## Common Issues

### Messages Not Being Sent

**Check the following:**

1. Ensure `SlackSender.config.enabled` is `true` (default)
2. Verify your profile is registered: `SlackSender.profile(:default)`
3. Check `SlackSender.config.sandbox_mode?` -- if `true`, check configured [`sandbox.behavior`](./configuration.md#sandbox-mode)
4. Check that an async backend is available if using `call` (not necessary for `call!`)
5. Verify your Slack token is valid and has the required scopes

### Messages Work in Production but Not in Development

When `SlackSender.config.sandbox_mode?` is enabled (by default, if `Rails.env.production?` is false), the configured [`sandbox.behavior`](./configuration.md#sandbox-mode) will apply.  This likely means logging but skipping send (if `:noop`) or redirecting to a specific channel.

**If messages are not received in the sandbox channel, check:**

1. `SlackSender.config.sandbox_mode?` — should be `true` in development
2. Your `sandbox.channel.replace_with` channel ID is correct
3. The bot is invited to the sandbox channel

### "NotInChannel" Errors

The bot must be invited to the channel.

**Resolution:**

*  Invite the bot to the channel (see [stackoverflow](https://stackoverflow.com/a/68475477))

### `missing_scope` Errors

Your Slack app is missing required OAuth scopes. The error message will tell you which scope is needed:

```
Missing required Slack scope 'files:write'. Add this scope to your Slack app at
https://api.slack.com/apps and reinstall the app.
```

(When sending a text message, this is prefixed with `"Unable to send Slack message: "`.)

**To fix:**

1. Go to https://api.slack.com/apps and select your app
2. Navigate to **OAuth & Permissions** → **Bot Token Scopes**
3. Add the missing scope (e.g., `files:write`)
4. Reinstall the app to your workspace

See [Required Slack Scopes](configuration.md#required-slack-scopes) for a complete list.

### File Uploads Fail with "channel ID required" Error

Slack's file upload APIs require channel IDs, not usernames or channel names:

```ruby
# These don't work for file uploads
SlackSender.call!(channel: "@username", file: file)
SlackSender.call!(channel: "#general", file: file)

# Use channel IDs instead
SlackSender.call!(channel: "C024BE91L", file: file)  # Public channel
SlackSender.call!(channel: "D032AC32T", file: file)  # DM channel
```

For DMs, find the DM channel ID (starts with `D`) from Slack's URL when viewing the conversation.

### File Uploads Fail with Async Delivery

File uploads with async delivery (`call`) are supported. Files are uploaded to Slack synchronously, then shared via the background job. Total file size cannot exceed `max_async_file_upload_size` (default 25 MB).

**If you're hitting the async size limit:**

```ruby
# Try increasing the async limit
SlackSender.config.max_async_file_upload_size = 100_000_000  # 100 MB
```

---

## FAQ

### How do I disable SlackSender temporarily?

Set `SlackSender.config.enabled = false`. All `call` and `call!` methods will return `false` without sending messages.

### Can I send to multiple channels at once?

Yes, use `channels:` (plural) with async delivery:

```ruby
SlackSender.call(channels: [:alerts, :ops], text: "Broadcast message")
```

Multi-channel is only supported for async (`call`). Sync (`call!`) requires sending to each channel individually (to avoid confusion about how to report on partial failures). Files are uploaded once and shared to all channels efficiently.

### Can I use multiple Slack workspaces?

Yes, register multiple profiles:

```ruby
SlackSender.register(:workspace1, token: TOKEN1, channels: {...})
SlackSender.register(:workspace2, token: TOKEN2, channels: {...})

SlackSender.profile(:workspace1).call(...)
SlackSender.profile(:workspace2).call(...)
```

### How are rate limits handled?

When sent async, SlackSender automatically detects rate limit errors and retries with the delay specified in Slack's `Retry-After` header. Retries happen up to 5 times before giving up.

### What errors are retried vs discarded?

**Retried:**
- Rate limit errors (with `Retry-After` delay)

**Discarded immediately (no retry):**
- `NotInChannel` — Bot not in channel
- `ChannelNotFound` — Channel doesn't exist
- `IsArchived` — Channel is archived

### How do I silence archived channel exceptions?

```ruby
SlackSender.config.silence_archived_channel_exceptions = true
```

This will log the error but not raise an exception.

### What's the difference between `call` and `call!`?

| Method | Delivery | Return Value | Retries |
|--------|----------|--------------|---------|
| `call` | Async (background job) | `true` or `false` | Yes (automatic) |
| `call!` | Sync (immediate) | Thread timestamp or `false` | No |

Use `call` by default. Use `call!` when you need the `thread_ts` for threading.

### How do I test SlackSender in my specs?

Stub at the profile level:

```ruby
allow(SlackSender.profile(:default)).to receive(:call).and_return(true)
allow(SlackSender.profile(:default)).to receive(:call!).and_return("1234567890.123456")
```

---

## Compatibility

- **Ruby**: >= 3.2.1
- **Dependencies**:
  - `axn` (>= 0.1.0-alpha.4.1, < 0.2.0)
  - `slack-ruby-client` (latest)
- **Optional dependencies**:
  - `sidekiq` or `active_job` (for async delivery)
  - `active_storage` (for ActiveStorage::Attachment file support)
