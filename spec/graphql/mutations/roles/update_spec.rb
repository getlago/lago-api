# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Roles::Update do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input: {id: role.id, name: new_name, description: new_description}}
    )
  end

  let(:query) do
    <<-GQL
      mutation($input: UpdateRoleInput!) {
        updateRole(input: $input) {
          id
          name
          description
        }
      }
    GQL
  end

  let(:required_permission) { "roles:update" }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:role) { create(:role, organization:, name: "Old Name", description: "Old description") }
  let(:new_name) { "New Name" }
  let(:new_description) { "New description" }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "roles:update"

  context "when role exists in the current organization" do
    it "updates the role" do
      result
      role.reload

      expect(role.name).to eq(new_name)
      expect(role.description).to eq(new_description)
    end

    it "returns updated role" do
      role_response = result["data"]["updateRole"]

      expect(role_response).to include(
        "id" => role.id,
        "name" => new_name,
        "description" => new_description
      )
    end
  end

  context "when role does not exist in the current organization" do
    let(:role) { create(:role) }

    it "returns an error" do
      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when role is predefined" do
    let(:role) { create(:role, :predefined, name: "Finance") }

    it "returns an error" do
      expect_graphql_error(result:, message: "predefined_role")
    end
  end
end
