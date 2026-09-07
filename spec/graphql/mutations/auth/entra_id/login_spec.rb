# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Auth::EntraId::Login, :premium, cache: :memory do
  let(:entra_id_integration) { create(:entra_id_integration, domain: "bar.com") }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:entra_id_token_response) { {"access_token" => "access_token"} }
  let(:entra_id_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:state) { SecureRandom.uuid }

  let(:mutation) do
    <<~GQL
      mutation($input: EntraIdLoginInput!) {
        entraIdLogin(input: $input) {
          user {
            email
          }
          token
        }
      }
    GQL
  end

  before do
    entra_id_integration

    if entra_id_integration
      entra_id_integration.organization.premium_integrations << "entra_id"
      entra_id_integration.organization.save!
      entra_id_integration.organization.enable_entra_id_authentication!
    end

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
          code: "code"
        }
      }
    )

    response = result["data"]["entraIdLogin"]

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
            code: "code"
          }
        }
      )

      response = result["errors"].first["extensions"]

      expect(response["status"]).to eq(422)
      expect(response["details"]["base"]).to include("domain_not_configured")
    end
  end
end
