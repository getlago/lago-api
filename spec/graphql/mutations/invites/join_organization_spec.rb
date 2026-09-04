# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invites::JoinOrganization do
  let(:membership) { create(:membership) }
  let(:user) { membership.user }
  let(:organization) { create(:organization) }
  let(:invite) { create(:invite, organization:, email: user.email) }

  let(:mutation) do
    <<~GQL
      mutation($input: JoinOrganizationInput!) {
        joinOrganization(input: $input) {
          id
          status
          organization {
            id
            name
          }
          user {
            id
            email
          }
        }
      }
    GQL
  end

  it "adds the authenticated user to the organization of the invite" do
    result = execute_graphql(
      current_user: user,
      login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD,
      query: mutation,
      variables: {input: {token: invite.token}}
    )

    data = result["data"]["joinOrganization"]

    expect(data["status"]).to eq("active")
    expect(data["organization"]["id"]).to eq(organization.id)
    expect(data["user"]["email"]).to eq(user.email)
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(query: mutation, variables: {input: {token: invite.token}})

      expect_unauthorized_error(result)
    end
  end

  context "when the invite targets another email" do
    let(:invite) { create(:invite, organization:, email: Faker::Internet.email) }

    it "returns an error" do
      result = execute_graphql(
        current_user: user,
        login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD,
        query: mutation,
        variables: {input: {token: invite.token}}
      )

      expect(result["errors"].first["extensions"]["status"]).to eq(422)
      expect(result["errors"].first["extensions"]["details"]["email"]).to eq(["invite_email_mistmatch"])
    end
  end

  context "when the invite is revoked" do
    let(:invite) { create(:invite, organization:, email: user.email, status: :revoked) }

    it "returns an error" do
      result = execute_graphql(
        current_user: user,
        login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD,
        query: mutation,
        variables: {input: {token: invite.token}}
      )

      expect(result["errors"].first["extensions"]["status"]).to eq(404)
      expect(result["errors"].first["extensions"]["details"]["invite"]).to eq(["not_found"])
    end
  end
end
