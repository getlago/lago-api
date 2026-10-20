# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CreditNotes::Create, :premium do
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "credit_notes:create" }
  let(:fee1) { create(:fee, invoice:) }
  let(:fee2) { create(:charge_fee, invoice:) }
  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      payment_status: "succeeded",
      currency: "EUR",
      fees_amount_cents: 100,
      taxes_amount_cents: 120,
      total_amount_cents: 120,
      total_paid_amount_cents: 110
    )
  end
  let(:mutation) do
    <<~GQL
      mutation($input: CreateCreditNoteInput!) {
        createCreditNote(input: $input) {
          id
          creditStatus
          refundStatus
          reason
          description
          currency
          totalAmountCents
          creditAmountCents
          balanceAmountCents
          refundAmountCents
          offsetAmountCents
          items {
            id
            amountCents
            amountCurrency
            fee { id }
          }
        }
      }
    GQL
  end

  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "credit_notes:create"

  it "creates a credit note" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          reason: "duplicated_charge",
          invoiceId: invoice.id,
          description: "Duplicated charge",
          creditAmountCents: 10,
          refundAmountCents: 5,
          offsetAmountCents: 10,
          items: [
            {
              feeId: fee1.id,
              amountCents: 10
            },
            {
              feeId: fee2.id,
              amountCents: 15
            }
          ]
        }
      }
    )

    result_data = result["data"]["createCreditNote"]

    expect(result_data["id"]).to be_present
    expect(result_data["creditStatus"]).to eq("available")
    expect(result_data["refundStatus"]).to eq("pending")
    expect(result_data["reason"]).to eq("duplicated_charge")
    expect(result_data["description"]).to eq("Duplicated charge")
    expect(result_data["currency"]).to eq("EUR")
    expect(result_data["totalAmountCents"]).to eq("25")
    expect(result_data["creditAmountCents"]).to eq("10")
    expect(result_data["balanceAmountCents"]).to eq("10")
    expect(result_data["refundAmountCents"]).to eq("5")
    expect(result_data["offsetAmountCents"]).to eq("10")

    expect(result_data["items"][0]["id"]).to be_present
    expect(result_data["items"][0]["amountCents"]).to eq("10")
    expect(result_data["items"][0]["amountCurrency"]).to eq("EUR")
    expect(result_data["items"][0]["fee"]["id"]).to eq(fee1.id)

    expect(result_data["items"][1]["id"]).to be_present
    expect(result_data["items"][1]["amountCents"]).to eq("15")
    expect(result_data["items"][1]["amountCurrency"]).to eq("EUR")
    expect(result_data["items"][1]["fee"]["id"]).to eq(fee2.id)
  end

  context "when crediting a contract product fee" do
    let(:invoice) do
      create(:invoice, customer:, organization:, payment_status: :succeeded, currency: "EUR", status: :finalized,
        fees_amount_cents: 100, total_amount_cents: 100, total_paid_amount_cents: 100, taxes_amount_cents: 0,
        version_number: 3)
    end
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    let(:fee1) do
      create(:fee, invoice:, subscription: nil, fee_type: :product, amount_cents: 100, precise_amount_cents: 100, taxes_rate: 0,
        invoiceable: contract_rate_card.rate_card.product, contract:, contract_rate_card:, rate_card_rate:, taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0)
    end
    let(:fee2) { nil }

    it "creates a partial credit against the invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {reason: "other", invoiceId: invoice.id, creditAmountCents: 50,
                            refundAmountCents: 0, items: [{feeId: fee1.id, amountCents: 50}]}}
      )

      expect(result.dig("data", "createCreditNote", "items").sole.dig("fee", "id")).to eq(fee1.id)
      expect(invoice.reload).to have_attributes(status: "finalized", total_amount_cents: 100)
      credit_note = CreditNote.find(result.dig("data", "createCreditNote", "id"))
      expect(credit_note.fees.sole.subscription_id).to be_nil
    end

    context "when the invoice belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer) }

      it "does not expose or credit the foreign invoice" do
        result = execute_graphql(current_user: membership.user, current_organization: organization,
          permissions: required_permission, query: mutation,
          variables: {input: {reason: "other", invoiceId: other_invoice.id, creditAmountCents: 50,
                              refundAmountCents: 0, items: [{feeId: fee1.id, amountCents: 50}]}})

        expect_not_found(result)
      end
    end
  end

  context "when invoice is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            reason: "duplicated_charge",
            invoiceId: "foo_id",
            creditAmountCents: 10,
            refundAmountCents: 5,
            items: [
              {
                feeId: fee1.id,
                amountCents: 15
              }
            ]
          }
        }
      )

      expect_not_found(result)
    end
  end

  context "when total amount is zero" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            reason: "duplicated_charge",
            invoiceId: invoice.id,
            creditAmountCents: 0,
            refundAmountCents: 0,
            items: [
              {
                feeId: fee1.id,
                amountCents: 0
              },
              {
                feeId: fee2.id,
                amountCents: 0
              }
            ]
          }
        }
      )

      expect_unprocessable_entity(result)
    end
  end

  context "with metadata" do
    let(:mutation) do
      <<~GQL
        mutation($input: CreateCreditNoteInput!) {
          createCreditNote(input: $input) {
            id
            metadata { key value }
          }
        }
      GQL
    end

    it "creates credit note with metadata" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            reason: "duplicated_charge",
            invoiceId: invoice.id,
            creditAmountCents: 10,
            refundAmountCents: 5,
            items: [{feeId: fee1.id, amountCents: 10}, {feeId: fee2.id, amountCents: 5}],
            metadata: [{key: "foo", value: "bar"}, {key: "baz", value: "qux"}]
          }
        }
      )

      result_data = result["data"]["createCreditNote"]
      expect(result_data["metadata"]).to match_array([
        {"key" => "foo", "value" => "bar"},
        {"key" => "baz", "value" => "qux"}
      ])
    end
  end
end
