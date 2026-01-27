# frozen_string_literal: true

FactoryBot.define do
  factory :profile, class: "SlackSender::Profile" do
    key { :test_profile }
    token { "SLACK_API_TOKEN" }
    channels { { slack_development: "C01H3KU3B9P", eng_alerts: "C03F1DMJ4PM" } }
    user_groups { { slack_development: "S123" } }
    slack_client_config { {} }
    sandbox do
      {
        channel: { replace_with: "C01H3KU3B9P" },
      }
    end

    initialize_with do
      new(
        key:,
        token:,
        channels:,
        user_groups:,
        slack_client_config:,
        sandbox:,
      )
    end
  end
end
