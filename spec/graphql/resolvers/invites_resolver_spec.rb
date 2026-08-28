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
