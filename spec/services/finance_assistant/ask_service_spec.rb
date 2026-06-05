# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinanceAssistant::AskService do
  subject(:result) { described_class.call(organization:, question:, session_id:) }

  let(:organization) { create(:organization) }
  let(:question) { "Show MRR for the past 3 months" }
  let(:session_id) { SecureRandom.uuid }
  let(:finance_assistant_url) { "http://finance-assistant.test" }

  around do |example|
    previous_url = ENV["LAGO_FINANCE_ASSISTANT_URL"]
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = finance_assistant_url
    example.run
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = previous_url
  end

  it "proxies the question to the finance assistant with the organization header" do
    request = stub_request(:post, "#{finance_assistant_url}/ask")
      .with(
        body: {
          question:,
          session_id:
        },
        headers: {
          "Content-Type" => "application/json",
          "X-Organization-Id" => organization.id
        }
      )
      .to_return(
        status: 200,
        body: {
          explanation: "Here is the result.",
          results: "| Month | MRR |",
          sql_query: "select * from invoices",
          session_id:,
          session_expired: false
        }.to_json
      )

    expect(result).to be_success
    expect(result.answer["explanation"]).to eq("Here is the result.")
    expect(result.answer["results"]).to eq("| Month | MRR |")
    expect(result.answer["sql_query"]).to eq("select * from invoices")
    expect(request).to have_been_requested
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
