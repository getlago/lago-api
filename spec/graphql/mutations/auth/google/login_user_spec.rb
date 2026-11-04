# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Auth::Google::LoginUser do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }
  let(:user) { membership.user }

  let(:login_result) do
    result = Auth::GoogleService::RESULTS.fetch(:login).new
    result.user = user
    result.token = "token"
    result
  end

  let(:mutation) do
    <<~GQL
      mutation($input: GoogleLoginUserInput!) {
        googleLoginUser(input: $input) {
          token
          needsOrganization
          user {
            id
            email
          }
        }
      }
    GQL
  end

  before do
    allow(Auth::GoogleService).to receive(:call).with(:login, "code", state: nil, state_secret: nil).and_return(login_result)
  end

  it "returns token and user" do
    result = execute_graphql(
      query: mutation,
      request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com")),
      variables: {
        input: {
          code: "code"
        }
      }
    )

    response = result["data"]["googleLoginUser"]

    expect(response["token"]).to eq("token")
    expect(response["user"]["id"]).to eq(user.id)
    expect(response["needsOrganization"]).to be(false)
    expect(response["user"]["email"]).to eq(user.email)
  end

  context "when user does not exist" do
    let(:login_result) do
      result = Auth::GoogleService::RESULTS.fetch(:login).new
      result.single_validation_failure!(error_code: "user_does_not_exist")
      result
    end

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com")),
        variables: {
          input: {
            code: "code"
          }
        }
      )

      response = result["errors"].first

      expect(response["extensions"]["status"]).to eq(422)
      expect(response["message"]).to eq("Unprocessable Entity")
    end
  end

  context "with a self-serve user who never had an organization" do
    let(:user) { create(:user, :self_serve) }

    include_context "with self-serve enabled"

    it "returns a session that needs an organization" do
      result = execute_graphql(
        query: mutation,
        request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com")),
        variables: {input: {code: "code"}}
      )

      expect(result["data"]["googleLoginUser"]["needsOrganization"]).to be(true)
    end
  end

  context "with a state" do
    before do
      allow(Auth::GoogleService).to receive(:call)
        .with(:login, "code", state: "state", state_secret: "secret").and_return(login_result)
    end

    it "passes the state and its secret to the service" do
      result = execute_graphql(
        query: mutation,
        request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com")),
        variables: {input: {code: "code", state: "state", stateSecret: "secret"}}
      )

      expect(result["data"]["googleLoginUser"]["token"]).to eq("token")
    end
  end

  context "when the state is invalid" do
    let(:login_result) { Auth::GoogleService::RESULTS.fetch(:login).new.single_validation_failure!(error_code: "invalid_google_state") }

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        request: Rack::Request.new(Rack::MockRequest.env_for("http://example.com")),
        variables: {input: {code: "code"}}
      )

      expect(result["errors"].first["extensions"]).to include("code" => "unprocessable_entity", "details" => {"base" => ["invalid_google_state"]})
    end
  end
end
