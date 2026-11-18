# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Auth::Google::AuthUrlResolver do
  let(:query) do
    <<~GQL
      query {
        googleAuthUrl {
          url
          stateSecret
        }
      }
    GQL
  end

  before do
    ENV["GOOGLE_AUTH_CLIENT_ID"] = "client_id"
    ENV["GOOGLE_AUTH_CLIENT_SECRET"] = "client_secret"
  end

  it "returns the google auth url" do
    result = execute_graphql(
      query:,
      request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com"))
    )

    response = result["data"]["googleAuthUrl"]

    expect(response["url"]).to include("https://accounts.google.com/o/oauth2/auth")
    expect(response["stateSecret"]).to be_nil
  end

  context "when self-serve is enabled" do
    include_context "with self-serve enabled"

    it "returns a state secret and a URL with a state and a PKCE challenge" do
      response = execute_graphql(query:)["data"]["googleAuthUrl"]

      expect(response["stateSecret"]).to be_present
      expect(response["url"]).to include("state=", "code_challenge=", "code_challenge_method=S256")
    end
  end

  context "when google auth is not setup" do
    before do
      ENV["GOOGLE_AUTH_CLIENT_ID"] = nil
      ENV["GOOGLE_AUTH_CLIENT_SECRET"] = nil
    end

    it "returns an error" do
      result = execute_graphql(
        query:,
        request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com"))
      )

      response = result["errors"].first

      expect(response["extensions"]["code"]).to eq("google_auth_missing_setup")
      expect(response["extensions"]["status"]).to eq(500)
    end
  end
end
