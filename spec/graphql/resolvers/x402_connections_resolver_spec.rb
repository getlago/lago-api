# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::X402ConnectionsResolver, :premium do
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
        x402Connections(limit: 5) {
          collection { id code cdpApiKeySecret }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let!(:connection) { create(:x402_connection, organization:) }

  before do
    create(:x402_connection, :discarded, organization:)
    create(:x402_connection)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns the organization's kept connections" do
    data = result["data"]["x402Connections"]

    expect(data["collection"]).to eq([{"id" => connection.id, "code" => connection.code, "cdpApiKeySecret" => "••••••••…ret"}])
    expect(data["metadata"]).to eq("currentPage" => 1, "totalCount" => 1)
  end

  context "without the x402_payments flag" do
    let(:organization) { create(:organization) }

    it "returns a feature unavailable error" do
      expect_forbidden_error(result)
    end
  end
end
