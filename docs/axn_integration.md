# Axn Integration

[← Back to README](../README.md)

SlackSender provides deep integration with [Axn](https://teamshares.github.io/axn/) for building Slack-enabled actions and dedicated notifier classes.

## Slack Strategy for Axn Actions

Add Slack messaging capabilities to any Axn action using the `:slack` strategy:

```ruby
class Deployments::Finish
  include Axn
  use :slack, channel: :deployments  # Default channel for all slack() calls

  expects :deployment, type: Deployment

  on_success { slack ":rocket: Deploy finished for `#{deployment.service}`" }
  on_failure { slack ":x: Deploy failed for `#{deployment.service}`", channel: :ops_alerts }

  def call
    # slack() is async (background job) - recommended for fire-and-forget
    slack "Finalizing deploy for `#{deployment.service}`..."

    # slack!() is sync - use when you need the thread_ts
    thread_ts = slack! "Starting rollout..."
    # ... rollout / status checks / persistence ...
    slack "Rollout complete!", thread_ts: thread_ts
  end
end
```

### Strategy Configuration

```ruby
use :slack, channel: :general             # Default channel for all slack() calls
use :slack, channel: :general, profile: :support  # Use a specific SlackSender profile
use :slack, channels: [:alerts, :ops]     # Default to multiple channels (async only)
use :slack                                # No default channel (must pass channel: each time)
```

### The `slack(...)` and `slack!(...)` Methods

The strategy adds two instance methods for sending Slack messages:

| Method | Delivery | Return Value | Use When |
|--------|----------|--------------|----------|
| `slack(...)` | Async (background job) | `true` or `false` | Default; enables auto-retry for rate limits |
| `slack!(...)` | Sync (immediate) | Thread timestamp or `false` | You need the `thread_ts` return value |

```ruby
# Async delivery (recommended) - uses Sidekiq or ActiveJob
slack "Hello world"
slack "Hello", channel: :other_channel

# Sync delivery - immediate execution, returns thread_ts
thread_ts = slack! "Starting deployment..."
slack! "Deployment finished", thread_ts: thread_ts

# Full kwargs work with both methods
slack text: "Hello", channel: :ops_alerts, icon_emoji: "robot"
slack! channel: :ops_alerts, blocks: [{ type: "section", text: { type: "mrkdwn", text: "*Bold*" } }]
```

**Note:** `slack(...)` requires an async backend to be configured (Sidekiq or ActiveJob). If no async backend is available, it raises `SlackSender::Error` with instructions to either use `slack!(...)` or configure an async backend.

---

## SlackSender::Notifier Base Class

For actions whose sole purpose is sending Slack notifications, inherit from `SlackSender::Notifier`. These are built on top of Axn (that's where the `expects` DSL comes from below), so you'll want to [familiarize yourself with that library](https://teamshares.github.io/axn/) before continuing:

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

---

## The `notify do ... end` DSL

The `notify` block groups all Slack message configuration together, keeping it visually separated from Axn declarations like `expects`:

```ruby
notify do
  channel :notifications           # Single channel
  text { "Hello!" }                # Dynamic text (block)
end

notify do
  channels :ops_alerts, :ic        # Multiple channels (files uploaded once, shared to all)
  only_if { priority == :high }    # Conditional send
  text :message_text               # Text from method
  attachments :build_attachments   # Attachments from method
end
```

### DSL Options

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

### Value Resolution

For each field, values are resolved in this order:
1. **Block**: `text { "dynamic #{value}" }` — evaluated in instance context
2. **Symbol**: `text :my_method` — calls method if it exists, otherwise treated as literal
3. **Literal**: `text "static"` — used as-is

### Required Fields

- At least one `channel` or `channels`
- At least one payload field (`text`, `blocks`, `attachments`, or `files`)

---

## Notifier Features

Since `SlackSender::Notifier` inherits from Axn, you get:
- `expects` / `exposes` for input/output contracts
- Hooks (`before`, `after`, `on_success`, `on_failure`)
- Automatic logging and error handling
- Async execution with `call_async`
