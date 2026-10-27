# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::X402ConnectionResolver, :premium do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id:}
    )
  end

  let(:required_permission) { "organization:integrations:view" }
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:membership) { create(:membership, organization:) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:id) { connection.id }
  let(:query) do
    <<~GQL
      query($id: ID!) {
        x402Connection(id: $id) { id name networks payoutAddresses { evm svm } }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns the connection" do
    expect(result["data"]["x402Connection"]).to eq(
      "id" => connection.id,
      "name" => connection.name,
      "networks" => connection.networks,
      "payoutAddresses" => {"evm" => connection.payout_addresses["evm"], "svm" => nil}
    )
  end

  context "when the connection belongs to another organization" do
    let(:id) { create(:x402_connection).id }

    it "returns a not found error" do
      expect_not_found(result)
    end
  end
end
