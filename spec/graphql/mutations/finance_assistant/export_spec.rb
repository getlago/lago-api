# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FinanceAssistant::Export do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input: {messageId: message_id}}
    )
  end

  let(:query) do
    <<~GQL
      mutation($input: ExportFinanceAssistantResultInput!) {
        exportFinanceAssistantResult(input: $input) {
          content
          filename
          rowCount
          truncated
        }
      }
    GQL
  end

  let(:required_permission) { "ai_conversations:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:message_id) { SecureRandom.uuid }
  let(:service_result) do
    BaseResult[:export].new.tap do |result|
      result.export = {
        "content" => "id,name\n1,alice\n",
        "filename" => "finance-assistant-#{message_id}.csv",
        "row_count" => 1,
        "truncated" => false
      }
    end
  end

  before do
    allow(FinanceAssistant::ExportService).to receive(:call).and_return(service_result)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:view"

  context "without premium feature" do
    it "returns an error" do
      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "with premium feature", :premium do
    it "returns the CSV export" do
      data = result["data"]["exportFinanceAssistantResult"]

      expect(data).to eq(
        "content" => "id,name\n1,alice\n",
        "filename" => "finance-assistant-#{message_id}.csv",
        "rowCount" => 1,
        "truncated" => false
      )
      expect(FinanceAssistant::ExportService).to have_received(:call).with(
        organization:,
        message_id:
      )
    end
  end
end
