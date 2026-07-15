# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinanceAssistant::AskService do
  subject(:result) { described_class.call(organization:, question:, session_id:) }

  let(:organization) { create(:organization) }
  let(:question) { "Show MRR for the past 3 months" }
  let(:session_id) { SecureRandom.uuid }
  let(:message_id) { SecureRandom.uuid }
  let(:finance_assistant_url) { "http://finance-assistant.test" }

  around do |example|
    previous_url = ENV["LAGO_FINANCE_ASSISTANT_URL"]
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = finance_assistant_url
    example.run
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = previous_url
  end

  it "proxies the question to the finance assistant with the api key header" do
    request = stub_request(:post, "#{finance_assistant_url}/ask")
      .with(
        body: {
          question:,
          session_id:
        },
        headers: {
          "Content-Type" => "application/json",
          "X-LAGO-API-KEY" => organization.api_keys.with_most_permissions.value
        }
      )
      .to_return(
        status: 200,
        body: {
          explanation: "Here is the result.",
          results: "| Month | MRR |",
          sql_query: "select * from invoices",
          session_id:,
          message_id:,
          session_expired: false
        }.to_json
      )

    expect(result).to be_success
    expect(result.answer["explanation"]).to eq("Here is the result.")
    expect(result.answer["results"]).to eq("| Month | MRR |")
    expect(result.answer["sql_query"]).to eq("select * from invoices")
    expect(result.answer["message_id"]).to eq(message_id)
    expect(request).to have_been_requested
  end

  context "when the finance assistant omits the optional sql_query" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask").to_return(
        status: 200,
        body: {
          explanation: "The agent failed to produce a valid answer. Please try again.",
          results: "",
          session_id:,
          message_id:,
          session_expired: false
        }.to_json
      )
    end

    it "returns a successful answer" do
      expect(result).to be_success
      expect(result.answer["sql_query"]).to be_nil
      expect(result.answer["results"]).to eq("")
    end
  end

  context "without a session id" do
    let(:session_id) { nil }

    it "omits the session id from the request body" do
      request = stub_request(:post, "#{finance_assistant_url}/ask")
        .with(body: {question:})
        .to_return(
          status: 200,
          body: {
            explanation: "Here is the result.",
            results: "| Month | MRR |",
            sql_query: "select * from invoices",
            session_id: SecureRandom.uuid,
            message_id:,
            session_expired: false
          }.to_json
        )

      expect(result).to be_success
      expect(request).to have_been_requested
    end
  end

  context "when the finance assistant returns a non-json success body" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask").to_return(status: 200, body: "<html>oops</html>")
    end

    it "returns an invalid response failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("finance_assistant_invalid_response")
    end
  end

  context "when the request to the finance assistant times out" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask").to_timeout
    end

    it "returns a service failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("finance_assistant_error")
    end
  end

  context "when the finance assistant returns an error without a detail" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask").to_return(status: 500, body: {}.to_json)
    end

    it "falls back to the http error message" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("finance_assistant_error")
      expect(result.error.error_message).to include("HTTP 500")
    end
  end

  context "when the question is blank" do
    let(:question) { "" }

    it "returns a validation failure without calling the finance assistant" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:question]).to eq(["value_is_mandatory"])
      expect(WebMock).not_to have_requested(:post, "#{finance_assistant_url}/ask")
    end
  end

  context "without finance assistant URL" do
    before do
      ENV["LAGO_FINANCE_ASSISTANT_URL"] = nil
    end

    it "returns a forbidden failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "when the finance assistant returns an error" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask")
        .to_return(status: 422, body: {detail: "Question cannot be empty"}.to_json)
    end

    it "returns a service failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("finance_assistant_error")
      expect(result.error.error_message).to eq("Question cannot be empty")
    end
  end

  context "when the finance assistant returns a malformed success response" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask")
        .to_return(status: 200, body: {explanation: "Missing the rest"}.to_json)
    end

    it "returns an invalid response failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("finance_assistant_invalid_response")
    end
  end

  context "when the finance assistant returns an empty success body" do
    before do
      stub_request(:post, "#{finance_assistant_url}/ask").to_return(status: 200, body: "")
    end

    it "returns an invalid response failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("finance_assistant_invalid_response")
    end
  end
end
