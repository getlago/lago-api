# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WalletTransactionResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        walletTransaction(id: $id) {
          id
          status
          amount
          transactionType
          failedAt
          invoice {
            id
            totalAmountCents
            payments {
              id
              amountCents
              amountCurrency
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:, status: :failed, failed_at: Time.current) }
  let(:invoice) { create(:invoice) }
  let(:fee) { create(:fee, invoice:, invoiceable: wallet_transaction, invoiceable_type: "WalletTransaction") }
  let(:payment) { create(:payment, payable: invoice, amount_cents: 1000, amount_currency: "EUR") }

  it "returns a single wallet transaction with its invoice and payments" do
    fee
    payment
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {id: wallet_transaction.id}
    )

    transaction_response = result["data"]["walletTransaction"]
    invoice_response = transaction_response["invoice"]
    payments_response = invoice_response["payments"]

    expect(transaction_response["id"]).to eq(wallet_transaction.id.to_s)
    expect(transaction_response["status"]).to eq(wallet_transaction.status)
    expect(transaction_response["failedAt"]).not_to be_nil
    expect(transaction_response["amount"]).to eq(wallet_transaction.amount.to_s)
    expect(transaction_response["transactionType"]).to eq(wallet_transaction.transaction_type)
    expect(invoice_response["id"]).to eq(invoice.id.to_s)
    expect(invoice_response["totalAmountCents"].to_i).to eq(invoice.total_amount_cents)
    expect(payments_response).not_to be_empty
    expect(payments_response.first["id"]).to eq(payment.id.to_s)
    expect(payments_response.first["amountCents"].to_i).to eq(payment.amount_cents)
    expect(payments_response.first["amountCurrency"]).to eq(payment.amount_currency)
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {id: wallet_transaction.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when not a member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
        variables: {id: wallet_transaction.id}
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end

  context "when transaction does not exist" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {id: "123456"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
