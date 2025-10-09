# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Memberships::Revoke do
  let(:required_permission) { "organization:members:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:mutation) do
    <<-GQL
      mutation($input: RevokeMembershipInput!) {
        revokeMembership(input: $input) {
          id
          revokedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:members:update"

  it "Revokes a membership" do
    membership_to_remove = create(:membership, organization:, role: :admin)

    result = execute_graphql(
      current_organization: organization,
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: membership_to_remove.id}
      }
    )

    data = result["data"]["revokeMembership"]

    expect(data["id"]).to eq(membership_to_remove.id)
    expect(data["revokedAt"]).to be_present
  end

  it "Cannot Revoke my own membership" do
    result = execute_graphql(
      current_organization: organization,
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: membership.id}
      }
    )

    aggregate_failures do
      expect(result["errors"].first["message"]).to eq("Method Not Allowed")
      expect(result["errors"].first["extensions"]["code"]).to eq("cannot_revoke_own_membership")
      expect(result["errors"].first["extensions"]["status"]).to eq(405)
    end
  end

  it "cannot revoke membership if it's the last admin of the organization" do
    # `finance` users normally don't have delete permissions on memberships
    # but here the permissions array is passed regardless of the actual user permission
    other_user = create(:membership, organization: organization, role: :finance)

    result = execute_graphql(
      current_organization: organization,
      current_user: other_user.user,
      current_membership: other_user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: membership.id}
      }
    )

    aggregate_failures do
      expect(result["errors"].first["message"]).to eq("Method Not Allowed")
      expect(result["errors"].first["extensions"]["code"]).to eq("last_admin")
      expect(result["errors"].first["extensions"]["status"]).to eq(405)
    end
  end
end
