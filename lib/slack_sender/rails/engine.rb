# frozen_string_literal: true

if defined?(Rails) && Rails.const_defined?(:Engine)
  module SlackSender
    module RailsIntegration
      class Engine < Rails::Engine
        engine_name "slack_sender_rails"

        initializer "slack_sender.add_slack_notifiers_to_autoload", after: :load_config_initializers do |app|
          notifiers_path = app.root.join("app/slack_notifiers")
          next unless File.directory?(notifiers_path)

          # Ensure the SlackNotifiers namespace module exists
          namespace = if Object.const_defined?(:SlackNotifiers)
                        Object.const_get(:SlackNotifiers)
                      else
                        Object.const_set(:SlackNotifiers, Module.new)
                      end

          Rails.autoloaders.main.push_dir(notifiers_path, namespace:)
        end
      end
    end
  end
end
