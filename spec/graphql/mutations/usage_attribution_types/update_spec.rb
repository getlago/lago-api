# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UsageAttributionTypes::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "usage_attribution_types:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:usage_attribution_type) do
    create(:usage_attribution_type, organization:, code: "user", name: "User", attribution_key: "user_id")
  end
  let(:parent) { create(:usage_attribution_type, organization:, code: "department") }

  let(:input) do
    {
      id: usage_attribution_type.id,
      code: "member",
      name: "Member",
      attributionKey: "employee_id",
      role: "hierarchical",
      parentId: parent.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateUsageAttributionTypeInput!) {
        updateUsageAttributionType(input: $input) {
          id code name attributionKey role
          parent { id code }
        }
      }
    GQL
  end

  before { organization.update!(feature_flags: ["account_tree"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "usage_attribution_types:update"

  it "updates the usage attribution type" do
    result_data = execution["data"]["updateUsageAttributionType"]

    expect(result_data["id"]).to eq(usage_attribution_type.id)
    expect(result_data["code"]).to eq("member")
    expect(result_data["name"]).to eq("Member")
    expect(result_data["attributionKey"]).to eq("employee_id")
    expect(result_data["parent"]["id"]).to eq(parent.id)
  end

  context "when the type belongs to another organization" do
    let(:usage_attribution_type) { create(:usage_attribution_type) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the account_tree feature flag is disabled" do
    before { organization.update!(feature_flags: []) }

    it "returns a forbidden error" do
      expect_graphql_error(result: execution, message: "forbidden")
    end
  end
end
