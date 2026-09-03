# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvitesResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query {
        invites(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:) }

  let_it_be(:membership) { create_default(:membership) }

  it "returns a list of invites" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: invite.organization,
      query:
    )

    invites_response = result["data"]["invites"]

    expect(invites_response["collection"].count).to eq(organization.invites.count)
    expect(invites_response["collection"].first["id"]).to eq(invite.id)

    expect(invites_response["metadata"]["currentPage"]).to eq(1)
    expect(invites_response["metadata"]["totalCount"]).to eq(1)
  end

  describe "filters" do
    let(:admin_role) { create(:role, :admin) }
    let(:finance_role) { create(:role, :finance) }

    let(:query) do
      <<~GQL
        query($searchTerm: String, $roleIds: [ID!]) {
          invites(limit: 5, searchTerm: $searchTerm, roleIds: $roleIds) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    let(:admin_invite) do
      create(:invite, organization:, email: "jane.doe@example.com", roles: [admin_role.code])
    end

    let(:finance_invite) do
      create(:invite, organization:, email: "john.doe@example.com", roles: [finance_role.code])
    end

    let(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables:
      )
    end

    before do
      admin_invite
      finance_invite
    end

    context "with a search term" do
      let(:variables) { {searchTerm: "jane"} }

      it "returns the invites matching the email" do
        invites_response = result["data"]["invites"]

        expect(invites_response["collection"].map { it["id"] }).to eq([admin_invite.id])
        expect(invites_response["metadata"]["totalCount"]).to eq(1)
      end
    end

    context "with role ids" do
      let(:variables) { {roleIds: [finance_role.id]} }

      it "returns the invites holding one of the roles" do
        invites_response = result["data"]["invites"]

        expect(invites_response["collection"].map { it["id"] }).to eq([finance_invite.id])
        expect(invites_response["metadata"]["totalCount"]).to eq(1)
      end
    end

    context "with both a search term and role ids" do
      let(:variables) { {searchTerm: "doe", roleIds: [admin_role.id]} }

      it "returns the invites matching every filter" do
        invites_response = result["data"]["invites"]

        expect(invites_response["collection"].map { it["id"] }).to eq([admin_invite.id])
        expect(invites_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:
      )

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end
end
