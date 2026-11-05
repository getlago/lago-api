# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::X402NetworksResolver, :premium do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )
  end

  let(:required_permission) { "organization:integrations:view" }
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:membership) { create(:membership, organization:) }
  let(:query) do
    <<~GQL
      query {
        x402Networks { id name family environment }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns every network a connection can accept" do
    expect(result["data"]["x402Networks"]).to eq([
      {"id" => "eip155:8453", "name" => "Base", "family" => "evm", "environment" => "mainnet"},
      {"id" => "eip155:84532", "name" => "Base Sepolia", "family" => "evm", "environment" => "testnet"},
      {"id" => "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", "name" => "Solana", "family" => "svm", "environment" => "mainnet"},
      {"id" => "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", "name" => "Solana Devnet", "family" => "svm", "environment" => "testnet"}
    ])
  end

  it "names every network" do
    expect(X402::Network::NAMES.keys).to match_array(X402::Network::NETWORKS.keys)
  end

  context "without the x402_payments flag" do
    let(:organization) { create(:organization) }

    it "returns a feature unavailable error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "without a premium license", premium: false do
    it "returns a feature unavailable error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end
end
