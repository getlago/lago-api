# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::WalletsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        customerPortalWallets {
          collection {
            id
            name
            currency
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, organization:, customer:) }

  before do
    wallet

    create(:wallet, status: :terminated, customer:, organization:)
  end

  it_behaves_like "requires a customer portal user"

  it "returns a list of active wallets", :aggregate_failures do
    result = execute_graphql(
      customer_portal_user: customer,
      query:
    )

    wallets_response = result["data"]["customerPortalWallets"]

    expect(wallets_response["collection"].count).to eq(customer.wallets.active.count)
    expect(wallets_response["collection"].first["id"]).to eq(wallet.id)
    expect(wallets_response["collection"].first["name"]).to eq(wallet.name)
    expect(wallets_response["collection"].first["currency"]).to eq(wallet.currency)
  end

  context "without customer portal user" do
    it "returns an error" do
      result = execute_graphql(
        query:
      )

      expect_unauthorized_error(result)
    end
  end
end
