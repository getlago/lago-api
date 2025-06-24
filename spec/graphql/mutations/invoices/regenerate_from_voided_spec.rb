# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::RegenerateFromVoided, type: :graphql do
  let(:required_permission) { "invoices:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:user) { membership.user }
  let(:plan) { create(:plan, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer, organization: organization, plan: plan) }
  let(:voided_invoice) { create(:invoice, status: :voided, organization: organization, customer: customer) }
  let!(:fee) { create(:fee, invoice: voided_invoice, subscription: subscription, organization: organization) }
  let(:fee_ids) { [fee.id] }

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
          feeIds: fee_ids
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
    # Invoice inexistente
    result = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          voidedInvoiceId: "non-existent-id",
          feeIds: fee_ids
        }
      }
    )
    expect(result["data"]["regenerateFromVoided"]).to be_nil
    expect(result["errors"]).to be_present

    # Invoice não voided
    non_voided_invoice = create(:invoice, status: :finalized, organization: organization, customer: customer)
    result2 = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          voidedInvoiceId: non_voided_invoice.id,
          feeIds: fee_ids
        }
      }
    )
    expect(result2["data"]["regenerateFromVoided"]).to be_nil
    expect(result2["errors"]).to be_present
  end
end
