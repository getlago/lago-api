# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WalletResolver do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        wallet(id: $id) {
          id name status creditsBalance
          recurringTransactionRules {
            transactionName
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, :with_recurring_transaction_rules, customer:) }

  before { wallet }

  it "returns a wallet" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {id: wallet.id}
    )

    coupon_response = result["data"]["wallet"]

    expect(coupon_response).to eq(
      {
        "creditsBalance" => 0.0, "id" => wallet.id, "name" => wallet.name, "recurringTransactionRules" => [{"transactionName" => "Recurring Transaction Rule"}], "status" => "active"
      }
    )
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {id: wallet.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when wallet is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {id: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
