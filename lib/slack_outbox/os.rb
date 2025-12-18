# frozen_string_literal: true

module SlackOutbox
  class OS < Base
    CHANNELS = {
      # Reminder: connect Teamshares Slackbot to each new channel that is added
      # by following these steps: https://stackoverflow.com/a/68475477
      slack_development: "C01H3KU3B9P", # slack-development
      eng_ops: "C08J3EEHVJL", # eng-ops
      eng_alerts: "C03F1DMJ4PM", # eng-alerts

      banking_overdraft: "C0976DWR8F3", # banking-overdraft
      cash_management: "C02P3S6SW91", # cash-distributions
      customer_group: "C026WRLJKFE", # shareholders-updates
      data_engineering_alerts: "C034ZRGLU4E", # data-engineering-alerts
      eo_share_issuance: "C02KX8LL5KM", # eo-share-issuance
      onestream: "C01UE3P26CW", # onestream
      os_feedback: "C02LHPA4K46", # os-feedback-and-support
      os_payroll_matching_review: "C08NRKJ03HD", # os-payroll-matching-review
      valuations: "C04L3AJ4DDK", # valuations-gaap
      valuations_alert: "C03ATPA6K7H", # valuations
    }.freeze

    USER_GROUPS = {
      overdraft_loan_alert: "S09UWME8VU0", # @overdraft-loan-alert-recipients
      slack_development: "SLACK_DEV_TEST_USER_GROUP_HANDLE", # @slack-dev-test-user-group
    }.freeze

    private

    # Overridable configuration methods
    def slack_token = ENV.fetch("SLACK_API_TOKEN")
    def dev_channel = CHANNELS[:slack_development]
    def error_channel = CHANNELS[:eng_alerts]
  end
end

