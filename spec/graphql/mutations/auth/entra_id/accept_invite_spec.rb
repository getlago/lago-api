# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Auth::EntraId::AcceptInvite, :premium, cache: :memory do
  let(:organization) { create(:organization, premium_integrations: ["entra_id"]) }
  let(:invite) { create(:invite, email: "foo@bar.com", organization:) }
  let(:entra_id_integration) { create(:entra_id_integration, domain: "bar.com", organization:) }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:entra_id_token_response) { {"access_token" => "access_token"} }
  let(:entra_id_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:state) { SecureRandom.uuid }

  let(:mutation) do
    <<~GQL
      mutation($input: EntraIdAcceptInviteInput!) {
        entraIdAcceptInvite(input: $input) {
          user {
            email
          }
          token
        }
      }
    GQL
  end

  before do
    invite
    entra_id_integration

    organization.enable_entra_id_authentication!

    Rails.cache.write(state, "foo@bar.com")

    allow(LagoHttpClient::Client).to receive(:new).and_return(lago_http_client)
    allow(lago_http_client).to receive(:post_url_encoded).and_return(entra_id_token_response)
    allow(lago_http_client).to receive(:get).and_return(entra_id_userinfo_response)
  end

  it "returns logged user" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          state:,
          code: "code",
          inviteToken: invite.token
        }
      }
    )

    response = result["data"]["entraIdAcceptInvite"]

    expect(response["user"]["email"]).to eq("foo@bar.com")
    expect(response["token"]).to be_present
  end

  context "when email domain is not configured with an integration" do
    let(:entra_id_integration) { nil }

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            state:,
            code: "code",
            inviteToken: invite.token
          }
        }
      )

      response = result["errors"].first["extensions"]

      expect(response["status"]).to eq(422)
      expect(response["details"]["base"]).to include("domain_not_configured")
    end
  end
end
