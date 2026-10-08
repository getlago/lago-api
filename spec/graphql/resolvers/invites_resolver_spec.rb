# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvitesResolver do
  let(:required_permission) { "organization:members:view" }
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

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:members:view"

  it "returns a list of invites" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: invite.organization,
      permissions: required_permission,
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
        permissions: required_permission,
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
        permissions: required_permission,
        query:
      )

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  describe "invite token" do
    subject(:tokens) do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        current_membership: membership,
        permissions:,
        query: token_query
      )

      result["data"]["invites"]["collection"].map { it["token"] }
    end

    let(:token_query) do
      <<~GQL
        query {
          invites(limit: 5) {
            collection { id token }
          }
        }
      GQL
    end

    let(:permissions) { %w[organization:members:view organization:members:create] }
    let(:invite_roles) { %w[finance] }
    let(:pending_invite) { create(:invite, organization:, roles: invite_roles) }

    before { pending_invite }

    context "when the member can create invites" do
      it "returns the token" do
        expect(tokens).to eq([pending_invite.token])
      end
    end

    context "when the member can only view members" do
      let(:permissions) { %w[organization:members:view] }

      it "does not return the token" do
        expect(tokens).to eq([nil])
      end
    end

    context "when the invite grants the admin role" do
      let(:invite_roles) { %w[admin] }

      context "with a non admin member" do
        it "does not return the token" do
          expect(tokens).to eq([nil])
        end
      end

      context "with an admin member" do
        let(:membership) { create(:membership, roles: %i[admin]) }

        it "returns the token" do
          expect(tokens).to eq([pending_invite.token])
        end
      end
    end
  end
end
