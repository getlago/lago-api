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
  let(:fees) { [fee.id] }

  let(:mutation) do
    <<~GQL
      mutation ($input: RegenerateInvoiceInput!) {
        regenerateFromVoided(input: $input) {
          id
          fees {
            id
          }
        }
      }
    GQL
  end

  let(:mutation_variables) do
    {
      input: {
        voidedInvoiceId: voided_invoice.id,
        fees: fees
      }
    }
  end

  it "regenerates an invoice from voided invoice" do
    result = execute_graphql(
      current_organization: organization,
      current_user: user,
      permissions: required_permission,
      query: mutation,
      variables: mutation_variables
    )

    expect(result["errors"]).to be_nil

    invoice_data = result["data"]["regenerateFromVoided"]
    expect(invoice_data["fees"]).to have(1).item
  end
end
