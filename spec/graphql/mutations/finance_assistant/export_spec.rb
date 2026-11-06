# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FinanceAssistant::Export do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions:,
      query:,
      variables: {input: {messageId: message_id}}
    )
  end

  let(:query) do
    <<~GQL
      mutation($input: ExportFinanceAssistantResultInput!) {
        exportFinanceAssistantResult(input: $input) {
          fileUrl
          filename
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:message_id) { SecureRandom.uuid }
  let(:file_url) { "http://api.lago.test/rails/active_storage/blobs/redirect/abc/finance_export.csv" }
  let(:filename) { "20260702120000_finance_export.csv" }
  let(:service_result) do
    BaseResult[:export].new.tap { |r| r.export = {file_url:, filename:} }
  end

  let(:required_permission) { "ai_conversations:view" }
  let(:permissions) { [required_permission, *AiConversations::ToolPolicy::FINANCE_ASSISTANT_PERMISSIONS] }

  let_it_be(:membership) { create_default(:membership) }

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
    context "when the member cannot view the billing data" do
      let(:permissions) { [required_permission, "analytics:view"] }

      it "returns a forbidden error without calling the finance assistant" do
        expect(result["data"]["exportFinanceAssistantResult"]).to be_nil
        expect_forbidden_error(result)
        expect(result["errors"].first["extensions"]["required_permissions"]).to include("invoices:view", "customers:view")
        expect(FinanceAssistant::ExportService).not_to have_received(:call)
      end
    end

    it "returns the signed download url and filename" do
      data = result["data"]["exportFinanceAssistantResult"]

      expect(data).to eq("fileUrl" => file_url, "filename" => filename)
      expect(FinanceAssistant::ExportService).to have_received(:call).with(
        organization:,
        message_id:
      )
    end
  end
end
