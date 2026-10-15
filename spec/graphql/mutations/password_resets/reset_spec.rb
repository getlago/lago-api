# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PasswordResets::Reset do
  include_context "with mocked security logger"

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership, organization:, user: create(:user, password: "HelloLago!1")) }
  let(:user) { membership.user }
  let(:password_reset) { create(:password_reset, user:) }

  let(:mutation) do
    <<~GQL
      mutation($input: ResetPasswordInput!) {
        resetPassword(input: $input) {
          token
        }
      }
    GQL
  end

  context "with a valid token" do
    subject(:result) do
      execute_graphql(
        query: mutation,
        variables: {
          input: {
            newPassword: "HelloLago!2",
            token: password_reset.token
          }
        }
      )
    end

    it "returns the auth token after a password reset" do
      data = result["data"]["resetPassword"]

      expect(data["token"]).to be_present
    end

    it_behaves_like "produces a security log", "user.password_edited" do
      before { result }
    end
  end

  context "when the password reset is expired" do
    let(:expired_password_reset) do
      create(:password_reset, user:, expire_at: Time.current - 1.minute)
    end

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            newPassword: "HelloLago!3",
            token: expired_password_reset.token
          }
        }
      )

      expect_not_found(result)
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }

    before { allow(Auth::AttemptsThrottle).to receive(:store).and_return(cache) }

    it "limits attempts per client IP" do
      20.times do
        execute_graphql(query: mutation, request:, variables: {input: {newPassword: "HelloLago!2", token: "invalid"}})
      end

      result = execute_graphql(
        query: mutation,
        request:,
        variables: {input: {newPassword: "HelloLago!2", token: password_reset.token}}
      )

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end
  end
end
