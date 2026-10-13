# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::LoginUser do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let(:user) { membership.user }
  let(:mutation) do
    <<~GQL
      mutation($input: LoginUserInput!) {
        loginUser(input: $input) {
          token
          user {
            id
            email
          }
        }
      }
    GQL
  end

  it "returns token and user" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email: user.email,
          password: "ILoveLago"
        }
      }
    )

    result_data = result["data"]["loginUser"]

    expect(result_data["token"]).to be_present
    expect(result_data["user"]["id"]).to eq(user.id)
  end

  context "with bad credentials" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: user.email,
            password: "badpassword"
          }
        }
      )

      expect_unprocessable_entity(result)
      expect(result["errors"].first.dig("extensions", "details").keys).to include("base")
      expect(result["errors"].first.dig("extensions", "details", "base")).to include("incorrect_login_or_password")
    end
  end

  context "with revoked membership" do
    let(:revoked_membership) { create(:membership, status: :revoked) }

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: revoked_membership.user.email,
            password: "ILoveLago"
          }
        }
      )

      expect_unprocessable_entity(result)
      expect(result["errors"].first.dig("extensions", "details").keys).to include("base")
      expect(result["errors"].first.dig("extensions", "details", "base")).to include("incorrect_login_or_password")
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    def login(password, email: user.email)
      execute_graphql(query: mutation, request:, variables: {input: {email:, password:}})
    end

    it "locks the email after 10 failed attempts, even with the right password" do
      10.times { login("badpassword") }

      result = login("ILoveLago")

      expect(result["data"]["loginUser"]).to be_nil
      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      expect(result["errors"].first.dig("extensions", "status")).to eq(429)
    end

    it "resets the failure count after a successful login" do
      9.times { login("badpassword") }
      login("ILoveLago")
      9.times { login("badpassword") }

      expect(login("ILoveLago")["data"]["loginUser"]["token"]).to be_present
    end

    it "limits attempts per client IP across emails" do
      30.times { |i| login("badpassword", email: "unknown-#{i}@example.com") }

      result = login("ILoveLago")

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end
  end
end
