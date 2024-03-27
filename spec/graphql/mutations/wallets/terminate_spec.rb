# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Wallets::Terminate, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateCustomerWalletInput!) {
        terminateCustomerWallet(input: $input) {
          id name status terminatedAt
        }
      }
    GQL
  end

  before { subscription }

  it "terminates a wallet" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {id: wallet.id}
      }
    )

    data = result["data"]["terminateCustomerWallet"]

    expect(data["id"]).to eq(wallet.id)
    expect(data["name"]).to eq(wallet.name)
    expect(data["status"]).to eq("terminated")
    expect(data["terminatedAt"]).to be_present
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {id: wallet.id}
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
