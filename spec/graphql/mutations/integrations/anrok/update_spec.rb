# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Anrok::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { "anrok1" }
  let(:name) { "Anrok 1" }
  let(:api_key) { "123456789" }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAnrokIntegrationInput!) {
        updateAnrokIntegration(input: $input) {
          id,
          code,
          name,
          apiKey
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates an anrok integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          name:,
          code:,
          apiKey: api_key
        }
      }
    )

    result_data = result["data"]["updateAnrokIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
      expect(result_data["apiKey"]).to eq("••••••••…789")
    end
  end
end
