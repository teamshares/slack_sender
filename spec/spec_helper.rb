# frozen_string_literal: true

require "bundler/setup"
require "sidekiq"
require "factory_bot"
Bundler.require(:default, :development)

require "slack_sender"
require "axn/testing/spec_helpers"

# Helper for building Slack API errors with properly-formed response objects.
# The gem's SlackError#error and #response_metadata methods call response.body.*,
# so we need to provide a response with a body that responds to these methods.
module SlackErrorHelper
  def self.build(error_class, error_code, response_metadata: nil)
    body = Struct.new(:error, :response_metadata, keyword_init: true).new(
      error: error_code,
      response_metadata:,
    )
    response = Struct.new(:body, keyword_init: true).new(body:)
    error_class.new(error_code, response)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    FactoryBot.find_definitions
  end
end
