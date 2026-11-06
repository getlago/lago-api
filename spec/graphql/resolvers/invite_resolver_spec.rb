# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InviteResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query($token: String!) {
        invite(token: $token) {
          id
          token
          email
          existingUser
          organization {
            id
            name
          }
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:) }

  let_it_be(:membership) { create_default(:membership) }

  it "returns a single invite" do
    result = execute_graphql(
      query:,
      variables: {
        token: invite.token
      }
    )

    data = result["data"]["invite"]

    expect(data["email"]).to eq(invite.email)
    expect(data["existingUser"]).to eq(false)
    expect(data["organization"]["name"]).to eq(organization.name)
  end

  it "does not expose the invite token to an anonymous caller" do
    result = execute_graphql(query:, variables: {token: invite.token})

    expect(result["data"]["invite"]["token"]).to be_nil
  end

  context "when the invited email belongs to an existing user" do
    before { create(:user, email: invite.email) }

    it "flags the invite as targeting an existing user" do
      result = execute_graphql(query:, variables: {token: invite.token})

      expect(result["data"]["invite"]["existingUser"]).to eq(true)
    end
  end

  context "when invite is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invite.organization,
        query:,
        variables: {
          token: "foo"
        }
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end
end
