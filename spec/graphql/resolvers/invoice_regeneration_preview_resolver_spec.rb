# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceRegenerationPreviewResolver do
  let(:required_permission) { "invoices:view" }
  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoiceRegenerationPreview(id: $id) {
          id
          number
          feesAmountCents
          couponsAmountCents
          creditNotesAmountCents
          prepaidCreditAmountCents
          refundableAmountCents
          creditableAmountCents
          paymentDisputeLosable
          paymentStatus
          taxesRate
          status
          customer {
            id
            name
            deletedAt
          }
          appliedTaxes {
            taxCode
            taxName
            taxRate
            taxDescription
            amountCents
            amountCurrency
          }
          fees {
            id
            itemType
            itemCode
            itemName
            creditableAmountCents
            taxesRate
            appliedTaxes {
              taxCode
              taxName
              taxRate
              taxDescription
              amountCents
              amountCurrency
            }
            charge {
              id
              billableMetric {
                code
                filters { key values }
              }
              filters { invoiceDisplayName values }
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:) }
  let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10, taxes_rate: 15) }
  let(:subscription) { invoice_subscription.subscription }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fee) do
    create(:fee, subscription:, invoice:, amount_cents: 50)
  end
  let(:charge_fee) do
    create(:charge_fee, subscription:, invoice:, amount_cents: 250, charge:)
  end
  let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }
  let(:fixed_charge_fee) do
    create(:fixed_charge_fee, subscription:, invoice:, amount_cents: 150, fixed_charge:)
  end

  before do
    fee
    charge_fee
    fixed_charge_fee
    invoice
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:view"

  it "returns a single invoice" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        id: invoice.id
      }
    )

    data = result["data"]["invoiceRegenerationPreview"]

    expect(data["id"]).to eq(invoice.id)
    expect(data["number"]).to eq(invoice.number)
    expect(data["paymentStatus"]).to eq(invoice.payment_status)
    expect(data["paymentDisputeLosable"]).to eq(true)
    expect(data["status"]).to eq(invoice.status)
    expect(data["taxesRate"]).to eq(0)
    expect(data["customer"]["id"]).to eq(customer.id)
    expect(data["customer"]["name"]).to eq(customer.name)

    expect(data["appliedTaxes"]).to be_empty

    subscription_fee = data["fees"].find { |f| f["itemType"] == "subscription" }
    expect(subscription_fee["id"]).to eq(fee.id)
    expect(subscription_fee["taxesRate"]).to eq(0)

    invoice_charge_fee = data["fees"].find { |f| f["itemType"] == "charge" }
    expect(invoice_charge_fee["id"]).to eq(charge_fee.id)
    expect(invoice_charge_fee["taxesRate"]).to eq(0)

    invoice_charge_fee = data["fees"].find { |f| f["itemType"] == "charge" }
    expect(invoice_charge_fee["id"]).to eq(charge_fee.id)
    expect(invoice_charge_fee["taxesRate"]).to eq(0)

    invoice_fixed_charge_fee = data["fees"].find { |f| f["itemType"] == "fixed_charge" }
    expect(invoice_fixed_charge_fee["id"]).to eq(fixed_charge_fee.id)
    expect(invoice_fixed_charge_fee["taxesRate"]).to eq(0)
  end

  context "when invoice is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invoice.organization,
        permissions: required_permission,
        query:,
        variables: {
          id: "foo"
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
