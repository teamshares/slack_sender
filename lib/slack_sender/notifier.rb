# frozen_string_literal: true

require_relative "notifier/notification_definition"
require_relative "notifier/notification_dsl"

module SlackSender
  # Base class for Axns whose primary purpose is sending Slack notifications.
  #
  # Usage:
  #   class MyNotifier < SlackSender::Notifier
  #     expects :user_id, type: Integer
  #
  #     notify do
  #       channel :notifications
  #       only_if { user.notifications_enabled? }
  #       text { "Hello #{user.name}!" }
  #     end
  #
  #     private
  #
  #     def user = @user ||= User.find(user_id)
  #   end
  #
  # DSL inside `notify do ... end`:
  #   channel :foo                    # single channel (symbol resolved as method or literal)
  #   channels :foo, :bar             # multiple channels
  #   text { "dynamic" }              # block evaluated in instance context
  #   text :method_name               # symbol resolved as method call
  #   text "static"                   # literal string
  #   only_if { condition }           # conditional send (block)
  #   only_if :method_name            # conditional send (symbol)
  #
  class Notifier
    include Axn

    use :slack

    class_attribute :_notification_definitions, default: []

    class << self
      # Declare a notification to send.
      #
      # @yield Block evaluated in NotificationDSL context to configure the notification
      #
      # @example Simple notification
      #   notify do
      #     channel :notifications
      #     text { "Hello!" }
      #   end
      #
      # @example With condition
      #   notify do
      #     channels :ops, :alerts
      #     only_if { priority == :high }
      #     text { "Alert: #{message}" }
      #   end
      #
      def notify(&)
        raise ArgumentError, "notify requires a block" unless block_given?

        dsl = NotificationDSL.new
        dsl.instance_eval(&)
        definition = dsl.build

        self._notification_definitions = _notification_definitions + [definition]
      end
    end

    def call
      self.class._notification_definitions.each do |definition|
        definition.execute(self)
      end
    end
  end
end
