# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::RegenerateFromVoided, type: :graphql do
  let(:required_permission) { "invoices:update" }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:user) { membership.user }
  let!(:add_on) { create(:add_on, organization:) }
  let(:fees) do
    [{
      id: fee.id,
      addOnId: add_on.id,
      description: "Updated description",
      invoiceDisplayName: "Updated display name",
      units: 5.0,
      unitAmountCents: 1000
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

  shared_examples "regenerates invoice with expected status" do |expected_status|
    it "regenerates an invoice with status #{expected_status}" do
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
      result_data = result.dig("data", "regenerateFromVoided")
      aggregate_failures do
        expect(result.dig("errors")).to be_nil
        expect(result_data.dig("id")).to be_present
        expect(result_data.dig("status")).to eq(expected_status)
        expect(result_data.dig("fees")&.size).to eq(1)
      end
    end
  end

  context "when customer has grace period" do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 1) }
    let(:voided_invoice) { create(:invoice, :voided, organization:, customer:) }
    let(:fee) { create(:fee, invoice: voided_invoice, organization:, add_on:) }

    include_examples "regenerates invoice with expected status", "draft"
  end

  context "when customer has no grace period" do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 0) }
    let(:voided_invoice) { create(:invoice, :voided, organization:, customer:) }
    let(:fee) { create(:fee, invoice: voided_invoice, organization:, add_on:) }

    include_examples "regenerates invoice with expected status", "finalized"
  end

  it "returns an error if the invoice is not found or not voided (failure)" do
    customer = create(:customer, organization:)
    voided_invoice = create(:invoice, :voided, organization:, customer:)
    fee = create(:fee, invoice: voided_invoice, organization:, add_on:)
    fees = [{
      id: fee.id,
      addOnId: add_on.id,
      description: "Updated description",
      invoiceDisplayName: "Updated display name",
      units: 5.0,
      unitAmountCents: 1000
    }]
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
    expect(result.dig("data", "regenerateFromVoided")).to be_nil
    expect(result.dig("errors")).to be_present

    non_voided_invoice = create(:invoice, status: :finalized, organization:, customer:)
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
    expect(result2.dig("data", "regenerateFromVoided")).to be_nil
    expect(result2.dig("errors")).to be_present
  end
end
