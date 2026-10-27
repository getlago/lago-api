# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::X402::Connections::Destroy, :premium do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: connection.id}}
    )
  end

  let(:required_permission) { "organization:integrations:delete" }
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:membership) { create(:membership, organization:) }
  let(:connection) { create(:x402_connection, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyX402ConnectionInput!) {
        destroyX402Connection(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:delete"

  it "discards the connection" do
    expect(result["data"]["destroyX402Connection"]["id"]).to eq(connection.id)
    expect(connection.reload).to be_discarded
  end

  context "without the x402_payments flag" do
    let(:organization) { create(:organization) }

    it "returns a feature unavailable error" do
      expect_forbidden_error(result)
      expect(connection.reload).not_to be_discarded
    end
  end
end
