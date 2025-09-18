# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Memberships::Update do
  let(:required_permission) { "organization:members:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:user) { membership.user }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateMembershipInput!) {
        updateMembership(input: $input) {
          id
          role
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:members:update"

  describe "Membership update mutation" do
    let(:membership_to_edit) { create(:membership, organization:, role: :finance) }

    it "returns the updated membership" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: membership_to_edit.id,
            role: "admin"
          }
        }
      )

      data = result["data"]["updateMembership"]

      expect(data["id"]).to eq(membership_to_edit.id)
      expect(data["role"]).to eq("admin")
    end
  end
end
