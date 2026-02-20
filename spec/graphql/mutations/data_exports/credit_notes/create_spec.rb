# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::DataExports::CreditNotes::Create do
  include_context "with mocked security logger"

  let(:required_permission) { "credit_notes:export" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateDataExportsCreditNotesInput!) {
        createCreditNotesDataExport(input: $input) {
          id,
          status,
       }
      }
    GQL
  end

  let(:variables) do
    {
      input: {
        format: "csv",
        resourceType: "credit_notes",
        filters: {
          amountFrom: 2000,
          amountTo: 5000,
          creditStatus: %w[available consumed],
          currency: "USD",
          customerExternalId: "abc123",
          issuingDateFrom: "2024-05-23",
          issuingDateTo: "2024-07-01",
          reason: %w[duplicated_charge product_unsatisfactory],
          refundStatus: %w[pending succeeded],
          searchTerm: "abc"
        }
      }
    }
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "credit_notes:export"

  context "with valid input" do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables:
      )
    end

    it "creates data export" do
      result_data = result["data"]["createCreditNotesDataExport"]

      expect(result_data).to include("id" => String, "status" => "pending")
    end

    it "produces a security log" do
      expect(security_logger).to have_received(:produce).with(
        organization: organization,
        log_type: "export",
        log_event: "export.created",
        user: membership.user,
        resources: hash_including(export_type: "credit_notes", resource_query: hash_including("currency" => "USD"))
      )
    end
  end
end
