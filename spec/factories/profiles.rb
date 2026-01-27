# frozen_string_literal: true

FactoryBot.define do
  factory :profile, class: "SlackSender::Profile" do
    key { :test_profile }
    token { "SLACK_API_TOKEN" }
    dev_channel { "C01H3KU3B9P" }
    channels { { slack_development: "C01H3KU3B9P", eng_alerts: "C03F1DMJ4PM" } }
    user_groups { { slack_development: "S123" } }
    dev_user_group { nil }
    dev_channel_redirect_prefix { nil }
    slack_client_config { {} }

    initialize_with do
      new(
        key:,
        token:,
        dev_channel:,
        dev_user_group:,
        channels:,
        user_groups:,
        slack_client_config:,
        dev_channel_redirect_prefix:,
      )
    end
  end
end
