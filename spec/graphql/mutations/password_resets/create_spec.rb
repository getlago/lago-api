# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PasswordResets::Create do
  include_context "with mocked security logger"

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let(:user) { membership.user }
  let(:email) { user.email }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePasswordResetInput!) {
        createPasswordReset(input: $input) {
          id
        }
      }
    GQL
  end

  context "with a valid user" do
    subject(:result) do
      execute_graphql(
        query: mutation,
        variables: {
          input: {
            email:
          }
        }
      )
    end

    it "creates a password reset for a user" do
      data = result["data"]["createPasswordReset"]

      expect(data["id"]).to be_present
    end

    it_behaves_like "produces a security log", "user.password_reset_requested" do
      before { result }
    end
  end

  context "with an unknown email" do
    def request_reset(email)
      execute_graphql(query: mutation, variables: {input: {email:}})
    end

    it "returns the same response shape as for a known email, without creating a reset" do
      known = request_reset(user.email)
      unknown = nil

      expect { unknown = request_reset("nobody@example.com") }.not_to change(PasswordReset, :count)

      expect(unknown["errors"]).to be_nil
      expect(unknown["data"]["createPasswordReset"]["id"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(unknown.to_json.length).to eq(known.to_json.length)
    end

    it "does not return the password reset id" do
      result = request_reset(user.email)

      expect(result["data"]["createPasswordReset"]["id"]).not_to eq(PasswordReset.last.id)
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "allows 3 requests per email per hour" do
      3.times { execute_graphql(query: mutation, variables: {input: {email:}}) }

      result = execute_graphql(query: mutation, variables: {input: {email:}})

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      expect(PasswordReset.where(user:).count).to eq(3)
    end
  end
end
