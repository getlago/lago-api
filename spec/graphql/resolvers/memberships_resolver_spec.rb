# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::MembershipsResolver do
  let(:query) do
    <<~GQL
      query {
        memberships(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount, adminCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership, roles: %i[admin]) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"

  it "returns a list of memberships" do
    create(:membership, organization: organization, roles: %i[admin])
    create_list(:membership, 2, organization: organization, roles: %i[finance])

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    memberships_response = result["data"]["memberships"]

    expect(memberships_response["collection"].count).to eq(4)
    expect(memberships_response["collection"].map { it["id"] }).to include(membership.id)

    expect(memberships_response["metadata"]["currentPage"]).to eq(1)
    expect(memberships_response["metadata"]["totalCount"]).to eq(4)
    expect(memberships_response["metadata"]["adminCount"]).to eq(2)
  end

  it "returns the count of active admin memberships" do
    create(:membership, organization: organization, roles: %i[admin], status: :revoked)
    create_list(:membership, 2, organization: organization, roles: %i[finance])

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    expect(result["data"]["memberships"]["metadata"]["adminCount"]).to eq(1)
  end

  describe "filters" do
    let(:admin_role) { create(:role, :admin) }
    let(:finance_role) { create(:role, :finance) }

    # The current user's own membership is pinned here: the default factory email is random
    # and could otherwise match the search terms exercised below.
    let(:membership) { create(:membership, roles: %i[manager], user: create(:user, email: "manager@lago.test")) }

    let(:query) do
      <<~GQL
        query($searchTerm: String, $roleIds: [ID!]) {
          memberships(limit: 5, searchTerm: $searchTerm, roleIds: $roleIds) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    let(:admin_membership) do
      create(:membership, organization:, role: admin_role, user: create(:user, email: "jane.doe@example.com"))
    end

    let(:finance_membership) do
      create(:membership, organization:, role: finance_role, user: create(:user, email: "john.doe@example.com"))
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
      admin_membership
      finance_membership
    end

    context "with a search term" do
      let(:variables) { {searchTerm: "jane"} }

      it "returns the memberships matching the user email" do
        memberships_response = result["data"]["memberships"]

        expect(memberships_response["collection"].map { it["id"] }).to eq([admin_membership.id])
        expect(memberships_response["metadata"]["totalCount"]).to eq(1)
      end
    end

    context "with role ids" do
      let(:variables) { {roleIds: [finance_role.id]} }

      it "returns the memberships holding one of the roles" do
        memberships_response = result["data"]["memberships"]

        expect(memberships_response["collection"].map { it["id"] }).to eq([finance_membership.id])
        expect(memberships_response["metadata"]["totalCount"]).to eq(1)
      end
    end

    context "with both a search term and role ids" do
      let(:variables) { {searchTerm: "doe", roleIds: [admin_role.id]} }

      it "returns the memberships matching every filter" do
        memberships_response = result["data"]["memberships"]

        expect(memberships_response["collection"].map { it["id"] }).to eq([admin_membership.id])
        expect(memberships_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  describe "traversal attack attempt" do
    let!(:other_org) { create(:organization) }

    let(:other_user) { create(:user) }
    let(:other_user_membership) { create(:membership, user: other_user, organization:) }
    let(:other_user_other_membership) { create(:membership, user: other_user, organization: other_org) }

    let(:query) do
      <<~GQL
        query {
          memberships(limit: 5) {
            collection {
              id
              user {
                organizations {
                  id #{organization_field}
                }
              }
            }
          }
        }
      GQL
    end

    let(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )
    end

    let(:other_org_result_data) do
      result.dig("data", "memberships", "collection")
        &.find { |h| h["id"] == other_user_membership.id }
        &.dig("user", "organizations")
        &.find { |h| h["id"] == other_org.id }
    end

    before do
      other_user
      other_user_membership
      other_user_other_membership
    end

    context "with non-sensitive field" do
      let(:organization_field) { "name" }

      it "allows the query" do
        expect(other_org_result_data).to eq(
          "id" => other_org.id,
          "name" => other_org.name
        )
      end
    end

    context "with sensitive field" do
      let(:organization_field) { "apiKey" }

      it "rejects the query for a sensitive field" do
        expect(other_org_result_data).to be nil
        expect_graphql_error(
          result:,
          message: "Field 'apiKey' doesn't exist on type 'Organization'"
        )
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
