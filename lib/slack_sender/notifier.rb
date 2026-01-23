# frozen_string_literal: true

module SlackSender
  # Base class for Axns whose primary purpose is sending Slack notifications.
  #
  # Usage:
  #   class MyNotifier < SlackSender::Notifier
  #     expects :user_id, type: Integer
  #
  #     notify_via channel: :notifications, text: :text, if: :should_notify?
  #
  #     def text = "Hello #{user.name}!"
  #     def should_notify? = user.notifications_enabled?
  #
  #     private
  #
  #     def user = @user ||= User.find(user_id)
  #   end
  #
  # DSL:
  #   notify_via channel: :foo, text: :text             # static channel, method for text
  #   notify_via channel: :channel, text: :text, if: :condition  # conditional send
  #   notify_via channel: [:a, :b], text: :text         # multi-channel
  #
  class Notifier
    include Axn

    use :slack

    class_attribute :_notify_via_configs, default: []

    class << self
      # Declare a notification to send.
      #
      # @param channel [Symbol, String, Array] Channel(s) to send to. Symbols are resolved as methods.
      # @param text [Symbol, String] Text content. Symbols are resolved as methods.
      # @param if [Symbol, Proc] Condition that must be truthy to send
      # @param unless [Symbol, Proc] Condition that must be falsy to send
      # @param kwargs [Hash] Additional SlackSender options (blocks:, attachments:, etc.)
      #
      def notify_via(**kwargs)
        self._notify_via_configs = _notify_via_configs + [kwargs.dup]
      end
    end

    def call
      self.class._notify_via_configs.each do |config|
        execute_notification(config.dup)
      end
    end

    private

    def execute_notification(config)
      # Extract conditions
      if_cond = config.delete(:if)
      unless_cond = config.delete(:unless)

      return if if_cond && !evaluate_condition(if_cond)
      return if unless_cond && evaluate_condition(unless_cond)

      # Extract channel separately (it may contain static symbols or method refs)
      raw_channel = config.delete(:channel)

      # Resolve remaining values (symbols that match methods become method calls)
      kwargs = config.transform_values { |v| resolve_value(v) }

      # Resolve channel(s) - only resolve if it's a method on this instance
      channels = Array(raw_channel).map { |ch| resolve_channel(ch) }

      # Handle multi-channel
      channels.each do |ch|
        slack(channel: ch, **kwargs.compact)
      end
    end

    def resolve_value(value)
      return value unless value.is_a?(Symbol)

      # Only resolve symbols that correspond to defined methods
      respond_to?(value, true) ? send(value) : value
    end

    def resolve_channel(value)
      return value unless value.is_a?(Symbol)

      # Only resolve if it's a method on this instance (not a static channel key)
      respond_to?(value, true) ? send(value) : value
    end

    def evaluate_condition(cond)
      case cond
      when Symbol then send(cond)
      when Proc then instance_exec(&cond)
      else cond
      end
    end
  end
end
