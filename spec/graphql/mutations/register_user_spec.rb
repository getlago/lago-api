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

  let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }

  def register(email)
    execute_graphql(query: mutation, request:, variables: {input: {email:, password: "ILoveLago", organizationName: "FooBar"}})
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

  context "with self-serve enabled" do
    subject(:result) { register(email) }

    let(:email) { "foo@bar.com" }

    include_context "with self-serve enabled"

    it "refuses with legacy_signup_disabled and creates nothing" do
      expect { result }.not_to change { [User.count, Organization.count, Membership.count] }
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "legacy_signup_disabled")
      expect(result["data"]["registerUser"]).to be_nil
    end

    it_behaves_like "does not produce a security log" do
      before { result }
    end

    context "with attempts throttling" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }

      before { Auth::AttemptsThrottle.store = cache }

      it "refuses before the attempt counts against the client IP, whose limit invites and password resets share" do
        20.times { register(email) }

        expect(Auth::AttemptsThrottle.hit!(:credentials_per_ip, "203.0.113.10")).to be(false)
      end
    end

    context "with an existing user's email" do
      let(:email) { create(:user).email }

      it "gives the same answer" do
        expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "legacy_signup_disabled")
      end
    end

    context "when signup is also disabled" do
      let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

      it "refuses with legacy_signup_disabled" do
        expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "legacy_signup_disabled")
      end
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:user) { create(:user) }

    before { Auth::AttemptsThrottle.store = cache }

    it "limits attempts per client IP" do
      20.times { register(user.email) }

      result = register("foo@bar.com")

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end
  end
end
