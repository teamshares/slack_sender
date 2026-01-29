# frozen_string_literal: true

# Shared examples for testing MissingScope error handling.
# Use these when testing code that catches and re-raises MissingScope errors
# with user-friendly messages.
#
# Required context:
# - `trigger_error` - a block/lambda that triggers the code path raising MissingScope
# - `response_body` - the mock Slack response body (can be overridden in nested contexts)
# - `response_env` - the mock Faraday env hash (can be overridden in nested contexts)
#
# Example usage:
#   context "when MissingScope error occurs" do
#     let(:response_body) { double("body", error: "missing_scope", needed: "chat:write", response_metadata: nil) }
#     let(:response_env) { { request_headers: {}, response_headers: {} } }
#     let(:trigger_error) { -> { subject.call! } }
#
#     before { allow(client).to receive(:chat_postMessage).and_raise(missing_scope_error) }
#
#     include_examples "missing scope error handling", expected_scope: "chat:write"
#   end
#
RSpec.shared_examples "missing scope error handling" do |expected_scope:|
  let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
  let(:missing_scope_error) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

  it "raises SlackSender::Error with the needed scope in the message" do
    expect { trigger_error.call }.to raise_error(SlackSender::Error, /#{expected_scope}/)
  end

  it "includes guidance about adding the scope" do
    expect { trigger_error.call }.to raise_error(SlackSender::Error, /Add this scope to your Slack app/)
  end
end

RSpec.shared_examples "missing scope error extraction from response_metadata" do |expected_scope:|
  let(:response_body) { double("body", error: "missing_scope", needed: nil, response_metadata: { "needed" => expected_scope }) }
  let(:response_env) { { request_headers: {}, response_headers: {} } }
  let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
  let(:missing_scope_error) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

  it "extracts scope from response_metadata" do
    expect { trigger_error.call }.to raise_error(SlackSender::Error, /#{expected_scope}/)
  end
end

RSpec.shared_examples "missing scope error extraction from HTTP headers" do |expected_scope:|
  let(:response_body) { double("body", error: "missing_scope", needed: nil, response_metadata: nil) }
  let(:response_env) { { request_headers: {}, response_headers: { "x-accepted-oauth-scopes" => expected_scope } } }
  let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
  let(:missing_scope_error) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

  it "extracts scope from x-accepted-oauth-scopes header" do
    expect { trigger_error.call }.to raise_error(SlackSender::Error, /#{expected_scope}/)
  end
end

RSpec.shared_examples "missing scope error with unknown scope" do
  let(:response_body) { double("body", error: "missing_scope", needed: nil, response_metadata: nil) }
  let(:response_env) { { request_headers: {}, response_headers: {} } }
  let(:faraday_response) { instance_double(Faraday::Response, body: response_body, env: response_env) }
  let(:missing_scope_error) { Slack::Web::Api::Errors::MissingScope.new("missing_scope", faraday_response) }

  it "raises SlackSender::Error with generic message" do
    expect { trigger_error.call }.to raise_error(SlackSender::Error, /Check your Slack app's OAuth scopes/)
  end
end
