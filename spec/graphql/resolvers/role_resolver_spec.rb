# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RoleResolver do
  let(:query) do
    <<~GQL
      query($roleId: ID!) {
        role(id: $roleId) {
          id name description admin permissions
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:current_organization) { membership.organization }
  let(:current_user) { membership.user }
  let(:permissions) { "roles:view" }
  let(:role) { create(:role, organization: current_organization) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "roles:view"

  it "returns a single role" do
    result = execute_graphql(
      current_user:,
      current_organization:,
      permissions:,
      query:,
      variables: {roleId: role.id}
    )

    expect(result["data"]["role"]).to include(
      "id" => role.id,
      "name" => role.name,
      "description" => role.description,
      "admin" => role.admin,
      "permissions" => %w[organization_view]
    )
  end

  context "with system role" do
    let(:admin_role) { create(:role, :admin) }

    it "returns system role" do
      result = execute_graphql(
        current_user:,
        current_organization:,
        permissions:,
        query:,
        variables: {roleId: admin_role.id}
      )

      expect(result["data"]["role"]).to include(
        "id" => admin_role.id,
        "name" => admin_role.name,
        "admin" => true
      )
    end
  end

  context "when role is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user:,
        current_organization:,
        permissions:,
        query:,
        variables: {roleId: "unknown"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when role belongs to another organization" do
    let(:other_role) { create(:role) }

    it "returns an error" do
      result = execute_graphql(
        current_user:,
        current_organization:,
        permissions:,
        query:,
        variables: {roleId: other_role.id}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
