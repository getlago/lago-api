# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Auth::EntraId::Authorize do
  let(:user) { create(:user) }
  let(:entra_id_integration) { create(:entra_id_integration) }

  let(:mutation) do
    <<~GQL
      mutation($input: EntraIdAuthorizeInput!) {
        entraIdAuthorize(input: $input) {
          url
        }
      }
    GQL
  end

  it "returns authorize url" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email: "foo@#{entra_id_integration.domain}"
        }
      }
    )

    response = result["data"]["entraIdAuthorize"]

    expect(response["url"]).to include(entra_id_integration.tenant_id)
  end

  context "when email domain is not configured with an integration" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: "foo@b.ar"
          }
        }
      )

      response = result["errors"].first["extensions"]

      expect(response["status"]).to eq(422)
      expect(response["details"]["base"]).to include("domain_not_configured")
    end
  end

  context "when invite token is provided" do
    let(:invite) { create(:invite, email: "foo@#{entra_id_integration.domain}") }

    it "returns authorize url" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: "foo@#{entra_id_integration.domain}",
            inviteToken: invite.token
          }
        }
      )

      response = result["data"]["entraIdAuthorize"]

      expect(response["url"]).to include(entra_id_integration.tenant_id)
    end
  end
end
