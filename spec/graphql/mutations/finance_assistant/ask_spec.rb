# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FinanceAssistant::Ask do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input: {question:, sessionId: session_id}}
    )
  end

  let(:query) do
    <<~GQL
      mutation($input: AskFinanceAssistantInput!) {
        askFinanceAssistant(input: $input) {
          explanation
          messageId
          results
          sessionId
          sessionExpired
          sqlQuery
        }
      }
    GQL
  end

  let(:required_permission) { "ai_conversations:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:question) { "Show MRR for the past 3 months" }
  let(:session_id) { SecureRandom.uuid }
  let(:message_id) { SecureRandom.uuid }
  let(:service_result) do
    BaseResult[:answer].new.tap do |result|
      result.answer = {
        "explanation" => "Here is the result.",
        "message_id" => message_id,
        "results" => "| Month | MRR |",
        "sql_query" => "select * from invoices",
        "session_id" => session_id,
        "session_expired" => false
      }
    end
  end

  before do
    allow(FinanceAssistant::AskService).to receive(:call).and_return(service_result)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  context "without premium feature" do
    it "returns an error" do
      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "with premium feature", :premium do
    it "returns a finance assistant answer" do
      data = result["data"]["askFinanceAssistant"]

      expect(data).to eq(
        "explanation" => "Here is the result.",
        "messageId" => message_id,
        "results" => "| Month | MRR |",
        "sessionId" => session_id,
        "sessionExpired" => false,
        "sqlQuery" => "select * from invoices"
      )
      expect(FinanceAssistant::AskService).to have_received(:call).with(
        organization:,
        question:,
        session_id:
      )
    end

    context "when the service fails" do
      let(:service_result) do
        BaseResult[:answer].new.tap do |result|
          result.service_failure!(code: "finance_assistant_error", message: "boom")
        end
      end

      it "returns a graphql error and no answer" do
        expect(result["data"]["askFinanceAssistant"]).to be_nil
        expect_graphql_error(result:, message: "finance_assistant_error")
      end
    end
  end
end
