# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UsageAttributionTypes::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "usage_attribution_types:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:input) do
    {
      code: "user",
      name: "User",
      attributionKey: "user_id",
      role: "hierarchical",
      parentId: parent.id
    }
  end

  let(:parent) { create(:usage_attribution_type, organization:, code: "department") }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateUsageAttributionTypeInput!) {
        createUsageAttributionType(input: $input) {
          id code name attributionKey role
          parent { id code }
        }
      }
    GQL
  end

  before { organization.update!(feature_flags: ["account_tree"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "usage_attribution_types:create"

  it "creates a usage attribution type" do
    result_data = execution["data"]["createUsageAttributionType"]

    expect(result_data["id"]).to be_present
    expect(result_data["code"]).to eq("user")
    expect(result_data["name"]).to eq("User")
    expect(result_data["attributionKey"]).to eq("user_id")
    expect(result_data["role"]).to eq("hierarchical")
    expect(result_data["parent"]["id"]).to eq(parent.id)
  end

  context "when the account_tree feature flag is disabled" do
    before { organization.update!(feature_flags: []) }

    it "returns a forbidden error" do
      expect_graphql_error(result: execution, message: "forbidden")
    end

    context "when the permission is also missing" do
      let(:required_permission) { [] }

      it "returns a missing permissions error" do
        expect_graphql_error(result: execution, message: "Missing permissions")
      end
    end
  end
end
