# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ApiKeys::Create do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:,
      variables: {input: {name:}}
    )
  end

  let(:query) do
    <<-GQL
      mutation($input: CreateApiKeyInput!) {
        createApiKey(input: $input) { id name value }
      }
    GQL
  end
  let(:name) { Faker::Lorem.word }

  let(:required_permission) { "developers:keys:manage" }

  let_it_be(:membership) { create_default(:membership) }

  include_context "with mocked security logger"

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:keys:manage"

  context "with premium organization", :premium do
    it "creates a new API key" do
      expect { result }.to change(ApiKey, :count).by(1)
    end

    it "returns created API key" do
      api_key_response = result["data"]["createApiKey"]

      expect(api_key_response["name"]).to eq(name)
    end

    it_behaves_like "produces a security log", "api_key.created" do
      before { result }
    end
  end

  context "with free organization" do
    it "returns an error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end
end
