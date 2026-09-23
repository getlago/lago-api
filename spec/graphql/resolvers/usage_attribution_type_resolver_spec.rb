# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::UsageAttributionTypeResolver do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: usage_attribution_type.id}
    )
  end

  let(:required_permission) { "usage_attribution_types:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:parent) { create(:usage_attribution_type, organization:, code: "department") }
  let(:usage_attribution_type) do
    create(:usage_attribution_type, organization:, code: "user", name: "User", attribution_keys: ["user_id"], parent:)
  end

  let(:query) do
    <<~GQL
      query($id: ID!) {
        usageAttributionType(id: $id) {
          id code name attributionKeys role
          parent { id code }
        }
      }
    GQL
  end

  before { organization.update!(feature_flags: ["account_tree"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "usage_attribution_types:view"

  it "returns a single usage attribution type" do
    result_data = result["data"]["usageAttributionType"]

    expect(result_data["id"]).to eq(usage_attribution_type.id)
    expect(result_data["code"]).to eq("user")
    expect(result_data["name"]).to eq("User")
    expect(result_data["attributionKeys"]).to eq(["user_id"])
    expect(result_data["role"]).to eq("hierarchical")
    expect(result_data["parent"]["id"]).to eq(parent.id)
  end

  context "when the usage attribution type does not exist" do
    let(:usage_attribution_type) { create(:usage_attribution_type) }

    it "returns a not found error" do
      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the usage attribution type is discarded" do
    before { usage_attribution_type.discard! }

    it "returns a not found error" do
      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the account_tree feature flag is disabled" do
    before { organization.update!(feature_flags: []) }

    it "returns a forbidden error" do
      expect_graphql_error(result:, message: "forbidden")
    end

    context "when the permission is also missing" do
      let(:required_permission) { [] }

      it "returns a missing permissions error" do
        expect_graphql_error(result:, message: "Missing permissions")
      end
    end
  end
end
