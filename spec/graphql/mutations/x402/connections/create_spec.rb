# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::X402::Connections::Create, :premium do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "organization:integrations:create" }
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:membership) { create(:membership, organization:) }
  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateX402ConnectionInput!) {
        createX402Connection(input: $input) {
          id code name facilitator asset networks allowedOrigins autoCreateCustomers
          cdpApiKeyId cdpApiKeySecret
          payoutAddresses { evm svm }
        }
      }
    GQL
  end

  let(:input) do
    {
      code: "coinbase_test",
      name: "Coinbase test",
      networks: ["eip155:84532"],
      payoutAddresses: {evm: evm_address, svm: nil},
      allowedOrigins: ["HTTPS://API.Example.com/"],
      autoCreateCustomers: false,
      cdpApiKeyId: cdp_api_key_id,
      cdpApiKeySecret: cdp_api_key_secret
    }
  end

  include_context "with CDP credentials"

  before do
    stub_cdp_supported
    stub_cdp_account(:evm, evm_address)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates the connection and never returns its secrets in clear" do
    data = result["data"]["createX402Connection"]

    expect(data).to include(
      "code" => "coinbase_test",
      "name" => "Coinbase test",
      "facilitator" => "coinbase_cdp",
      "asset" => "usdc",
      "networks" => ["eip155:84532"],
      "allowedOrigins" => ["https://api.example.com"],
      "autoCreateCustomers" => false,
      "payoutAddresses" => {"evm" => evm_address, "svm" => nil}
    )
    expect(data["cdpApiKeyId"]).to eq("••••••••…#{cdp_api_key_id[-3..]}")
    expect(data["cdpApiKeySecret"]).to eq("••••••••…#{cdp_api_key_secret[-3..]}")
    expect(organization.x402_connections.sole.payout_addresses).to eq("evm" => evm_address)
  end

  context "when a field is invalid" do
    let(:input) { super().merge(networks: ["eip155:84532", "eip155:8453"], allowedOrigins: ["https://*.example.com"]) }

    it "returns the error codes per field" do
      expect_graphql_error(result:, message: "unprocessable_entity")
      expect(result["errors"].first["extensions"]["details"]).to include(
        "networks" => ["mixed_environments"],
        "allowedOrigins" => ["invalid_format"]
      )
    end
  end

  context "when a payout address of a selected family is missing" do
    let(:input) { super().merge(networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]) }

    it "keys the error by family" do
      expect_unprocessable_entity(result, details: {payoutAddresses: {svm: ["value_is_mandatory"]}})
    end
  end

  context "when CDP refuses the key" do
    before { stub_cdp_supported(status: 401, body: "Unauthorized") }

    it "returns the error on the key" do
      expect_unprocessable_entity(result, details: {cdpApiKey: ["invalid_credentials"]})
    end
  end

  context "without the x402_payments flag" do
    let(:organization) { create(:organization) }

    it "returns a feature unavailable error" do
      expect_forbidden_error(result)
      expect(organization.x402_connections).to be_empty
    end
  end
end
