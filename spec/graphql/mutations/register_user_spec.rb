# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RegisterUser do
  include_context "with mocked security logger"

  before { create(:role, :admin) }

  let(:mutation) do
    <<~GQL
      mutation($input: RegisterUserInput!) {
        registerUser(input: $input) {
          token
          user {
            id
            email
          }
          organization {
            id
            name
          }
          membership {
            id
          }
        }
      }
    GQL
  end

  context "with a valid new user" do
    subject(:result) do
      execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: "foo@bar.com",
            password: "ILoveLago",
            organizationName: "FooBar"
          }
        }
      )
    end

    it "returns user, organization and membership" do
      expect(result["data"]["registerUser"]["membership"]["id"]).to be_present
      expect(result["data"]["registerUser"]["user"]["email"]).to eq("foo@bar.com")
      expect(result["data"]["registerUser"]["organization"]["name"]).to eq("FooBar")
      expect(result["data"]["registerUser"]["token"]).to be_present
    end

    it_behaves_like "produces a security log", "user.signed_up" do
      before { result }
    end
  end

  context "with already existing user" do
    subject(:result) do
      execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: user.email,
            password: "ILoveLago",
            organizationName: "FooBar"
          }
        }
      )
    end

    let(:user) { create(:user) }

    it "returns an error" do
      expect_unprocessable_entity(result)
      expect(result["errors"].first.dig("extensions", "details").keys).to include("email")
      expect(result["errors"].first.dig("extensions", "details", "email")).to include("user_already_exists")
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }
    let(:user) { create(:user) }

    before { Auth::AttemptsThrottle.store = cache }

    def register(email)
      execute_graphql(query: mutation, request:, variables: {input: {email:, password: "ILoveLago", organizationName: "FooBar"}})
    end

    it "limits attempts per client IP" do
      20.times { register(user.email) }

      result = register("foo@bar.com")

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end
  end
end
