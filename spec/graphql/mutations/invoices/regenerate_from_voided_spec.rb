# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::RegenerateFromVoided, type: :graphql do
  let(:required_permission) { "invoices:update" }
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:voided_invoice) { create(:invoice, :voided, organization: organization) }
  let!(:fee) { create(:fee, invoice: voided_invoice, organization: organization) }
  let(:fees) do
    [{
      id: fee.id,
      add_on_id: nil,
      description: "Updated description",
      invoice_display_name: "Updated display name",
      units: 5.0,
      unit_amount_cents: 1000
    }]
  end

  let(:mutation) do
    <<~GQL
      mutation ($input: RegenerateInvoiceInput!) {
        regenerateFromVoided(input: $input) {
          id
          status
          fees {
            id
          }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:update"

  it "regenerates an invoice from a voided invoice (success)" do
    result = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          voidedInvoiceId: voided_invoice.id,
          fees: fees
        }
      }
    )

    result_data = result["data"]["regenerateFromVoided"]
    aggregate_failures do
      expect(result["errors"]).to be_nil
      expect(result_data["id"]).to be_present
      expect(result_data["status"]).to eq("draft")
      expect(result_data["fees"].length).to eq(1)
    end
  end

  it "returns an error if the invoice is not found or not voided (failure)" do
    result = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          voidedInvoiceId: "non-existent-id",
          fees: fees
        }
      }
    )
    expect(result["data"]["regenerateFromVoided"]).to be_nil
    expect(result["errors"]).to be_present

    non_voided_invoice = create(:invoice, status: :finalized, organization: organization, customer: customer)
    result2 = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          voidedInvoiceId: non_voided_invoice.id,
          fees: fees
        }
      }
    )
    expect(result2["data"]["regenerateFromVoided"]).to be_nil
    expect(result2["errors"]).to be_present
  end
end
