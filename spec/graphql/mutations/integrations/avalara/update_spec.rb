# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Avalara::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:avalara_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { "avalara1" }
  let(:name) { "Avalara 1" }
  let(:account_id) { "acc-id-1" }
  let(:license_key) { "123456789" }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAvalaraIntegrationInput!) {
        updateAvalaraIntegration(input: $input) {
          id,
          code,
          name,
          accountId,
          licenseKey
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["avalara"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates an avalara integration" do
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
          accountId: account_id,
          licenseKey: license_key
        }
      }
    )

    result_data = result["data"]["updateAvalaraIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
    end
  end
end
