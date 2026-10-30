# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::X402::Connections::Update, :premium do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "organization:integrations:update" }
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:membership) { create(:membership, organization:) }
  let(:connection) { create(:x402_connection, organization:, cdp_api_key_id:, cdp_api_key_secret:) }
  let(:evm_address) { connection.payout_addresses["evm"] }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateX402ConnectionInput!) {
        updateX402Connection(input: $input) {
          id name allowedOrigins cdpApiKeySecret
        }
      }
    GQL
  end

  let(:input) { {id: connection.id, name: "Renamed", allowedOrigins: ["https://example.com", "http://localhost:3000"]} }

  include_context "with CDP credentials"

  before do
    stub_cdp_supported
    stub_cdp_account(:evm, evm_address)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates the connection" do
    expect(result["data"]["updateX402Connection"]).to include(
      "name" => "Renamed",
      "allowedOrigins" => ["https://example.com", "http://localhost:3000"]
    )
  end

  context "when the form sends back the masked secrets" do
    let(:input) do
      super().merge(cdpApiKeyId: "••••••••…x02", cdpApiKeySecret: "••••••••…abc")
    end

    it "keeps the stored secrets" do
      expect(result["errors"]).to be_nil
      expect(connection.reload).to have_attributes(name: "Renamed", cdp_api_key_id:, cdp_api_key_secret:)
    end
  end

  context "when the form sends back only the masked key id" do
    let(:input) { super().merge(cdpApiKeyId: "••••••••…x02") }

    it "keeps the stored key id" do
      expect(result["errors"]).to be_nil
      expect(connection.reload.cdp_api_key_id).to eq(cdp_api_key_id)
    end
  end

  context "when a new secret is typed" do
    let(:new_signing_key) { OpenSSL::PKey.generate_key("ED25519") }
    let(:new_secret) { Base64.strict_encode64(new_signing_key.raw_private_key + new_signing_key.raw_public_key) }
    let(:input) { super().merge(cdpApiKeySecret: new_secret) }

    it "stores it" do
      result

      expect(connection.reload.cdp_api_key_secret).to eq(new_secret)
    end
  end

  context "when the connection belongs to another organization" do
    let(:connection) { create(:x402_connection) }

    it "returns a not found error" do
      expect_not_found(result)
    end
  end

  context "without the x402_payments flag" do
    let(:organization) { create(:organization) }

    it "returns a feature unavailable error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end
end
