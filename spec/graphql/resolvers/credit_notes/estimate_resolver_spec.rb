# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CreditNotes::EstimateResolver, :premium do
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query($invoiceId: ID!, $items: [CreditNoteItemInput!]!) {
        creditNoteEstimate(invoiceId: $invoiceId, items: $items) {
          currency
          taxesAmountCents
          subTotalExcludingTaxesAmountCents
          maxCreditableAmountCents
          maxRefundableAmountCents
          couponsAdjustmentAmountCents
          taxesRate
          items { amountCents fee { id } }
          appliedTaxes { id amountCents }
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:fees) do
    create_list(
      :fee,
      2,
      invoice:,
      amount_cents: 100,
      precise_coupons_amount_cents: 50
    )
  end
  let(:coupon) do
    create(
      :coupon,
      organization:,
      amount_cents: 100,
      expiration: :no_expiration,
      coupon_type: :fixed_amount,
      frequency: :forever
    )
  end
  let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }
  let(:credit) { create(:credit, invoice:, applied_coupon:, amount_cents: 100) }

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before { credit }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "credit_notes:create"

  it "returns the estimate for the credit note creation" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "credit_notes:create",
      query:,
      variables: {
        invoiceId: invoice.id,
        items: fees.map { |f| {feeId: f.id, amountCents: 50} }
      }
    )

    estimate_response = result["data"]["creditNoteEstimate"]

    expect(estimate_response["currency"]).to eq("EUR")
    expect(estimate_response["taxesAmountCents"]).to eq("0")
    expect(estimate_response["subTotalExcludingTaxesAmountCents"]).to eq("50")
    expect(estimate_response["maxCreditableAmountCents"]).to eq("50")
    expect(estimate_response["maxRefundableAmountCents"]).to eq("0")
    expect(estimate_response["couponsAdjustmentAmountCents"]).to eq("50")
    expect(estimate_response["items"].first["amountCents"]).to eq("50")
    expect(estimate_response["appliedTaxes"]).to be_blank
  end

  context "with a contract product fee" do
    let(:invoice) do
      create(:invoice, organization:, customer:, payment_status: :succeeded, currency: "EUR", status: :finalized,
        fees_amount_cents: 100, total_amount_cents: 100, total_paid_amount_cents: 100, taxes_amount_cents: 0,
        version_number: 3)
    end
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    let(:fee) do
      create(:fee, invoice:, subscription: nil, fee_type: :product, amount_cents: 100, precise_amount_cents: 100, taxes_rate: 0,
        invoiceable: contract_rate_card.rate_card.product, contract:, contract_rate_card:, rate_card_rate:, taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0)
    end
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer) }
    let(:other_contract) { create(:contract, organization: other_organization, customer: other_customer) }
    let(:other_rate_card) { create(:contract_rate_card, organization: other_organization, contract: other_contract) }
    let(:other_rate_card_rate) { create(:rate_card_rate, organization: other_organization, rate_card: other_rate_card.rate_card) }
    let(:foreign_fee) do
      create(:fee, invoice: other_invoice, subscription: nil, fee_type: :product, amount_cents: 100, precise_amount_cents: 100,
        invoiceable: other_rate_card.rate_card.product, contract: other_contract, contract_rate_card: other_rate_card,
        rate_card_rate: other_rate_card_rate, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
    end

    it "estimates a partial credit without requiring a subscription" do
      result = execute_graphql(current_user: membership.user, current_organization: organization,
        permissions: "credit_notes:create", query:,
        variables: {invoiceId: invoice.id, items: [{feeId: fee.id, amountCents: 40}]})

      estimate = result.dig("data", "creditNoteEstimate")
      expect(estimate["subTotalExcludingTaxesAmountCents"]).to eq("40")
      expect(estimate["items"].sole.dig("fee", "id")).to eq(fee.id)
      expect(invoice.reload).to have_attributes(status: "finalized", total_amount_cents: 100)
    end

    it "rejects a fee ID from another organization" do
      result = execute_graphql(current_user: membership.user, current_organization: organization,
        permissions: "credit_notes:create", query:,
        variables: {invoiceId: invoice.id, items: [{feeId: foreign_fee.id, amountCents: 40}]})

      expect_not_found(result)
    end
  end

  context "with invalid invoice" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "credit_notes:create",
        query:,
        variables: {
          invoiceId: create(:invoice).id,
          items: fees.map { |f| {feeId: f.id, amountCents: 50} }
        }
      )

      expect_not_found(result)
    end
  end
end
