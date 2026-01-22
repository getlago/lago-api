# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Memberships::Update do
  let(:required_permission) { "organization:members:update" }
  let(:admin_role) { create(:role, :admin) }
  let(:finance_role) { create(:role, :finance) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:user) { membership.user }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateMembershipInput!) {
        updateMembership(input: $input) {
          id
          roles
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:members:update"

  describe "Membership update mutation" do
    let(:membership_to_edit) { create(:membership, organization:) }

    before do
      create(:membership_role, membership: membership_to_edit, role: finance_role)
      create(:membership_role, membership:, role: admin_role)
    end

    it "returns the updated membership" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: membership_to_edit.id,
            roles: %w[admin]
          }
        }
      )

      data = result["data"]["updateMembership"]

      expect(data["id"]).to eq(membership_to_edit.id)
      expect(data["roles"]).to eq(%w[Admin])
    end
  end
end
