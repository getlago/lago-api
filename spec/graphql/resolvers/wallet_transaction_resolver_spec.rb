# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WalletTransactionResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($transactionId: ID!) {
        walletTransaction(transactionId: $transactionId) {
          id
          status
          amount
          transactionType
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

  before do
    wallet_transaction
  end

  it "returns a single wallet transaction" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        transactionId: wallet_transaction.id
      }
    )
    pp result

    transaction_response = result["data"]["walletTransaction"]

    aggregate_failures do
      expect(transaction_response["id"]).to eq(wallet_transaction.id)
      expect(transaction_response["status"]).to eq(wallet_transaction.status)
      expect(transaction_response["amount"]).to eq(wallet_transaction.amount.to_s)
      expect(transaction_response["transactionType"]).to eq(wallet_transaction.transaction_type)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {
          transactionId: wallet_transaction.id
        }
      )

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  context "when not a member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
        variables: {
          transactionId: wallet_transaction.id
        }
      )

      expect_graphql_error(
        result:,
        message: "Not in organization"
      )
    end
  end

  context "when transaction does not exist" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          transactionId: "123456"
        }
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end
end
