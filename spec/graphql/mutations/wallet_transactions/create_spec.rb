# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WalletTransactions::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, balance: 10.0, credits_balance: 10.0) }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateCustomerWalletTransactionInput!) {
        createCustomerWalletTransaction(input: $input) {
          collection { id, status }
        }
      }
    GQL
  end

  before do
    subscription
    wallet
  end

  it "create a wallet transaction" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          walletId: wallet.id,
          paidCredits: "5.00",
          grantedCredits: "5.00"
        }
      }
    )

    result_data = result["data"]["createCustomerWalletTransaction"]

    aggregate_failures do
      expect(result_data["collection"].count).to eq(2)
      expect(result_data["collection"].first["status"]).to eq("pending")
      expect(result_data["collection"].last["status"]).to eq("settled")
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            walletId: wallet.id,
            paidCredits: "5.00",
            grantedCredits: "5.00"
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            walletId: wallet.id,
            paidCredits: "5.00",
            grantedCredits: "5.00"
          }
        }
      )

      expect_forbidden_error(result)
    end
  end
end
