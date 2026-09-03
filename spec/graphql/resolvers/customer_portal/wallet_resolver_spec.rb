# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::WalletResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query($walletId: ID!) {
        customerPortalWallet(id: $walletId) {
          id
          name
          priority
          currency
          status
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:wallet) { create(:wallet, organization:, customer:) }

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    customer
  end

  it_behaves_like "requires a customer portal user"

  it "returns a single wallet" do
    result = execute_graphql(
      customer_portal_user: customer,
      query:,
      variables: {walletId: wallet.id}
    )

    wallet_response = result["data"]["customerPortalWallet"]
    expect(wallet_response).to include(
      "id" => wallet.id,
      "name" => wallet.name,
      "priority" => wallet.priority,
      "currency" => wallet.currency,
      "status" => wallet.status
    )
  end

  context "when wallet is not found" do
    it "returns an error" do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {walletId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
