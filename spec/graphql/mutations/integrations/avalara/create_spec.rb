# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Avalara::Create, type: :graphql do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:code) { "avalara1" }
  let(:name) { "Avalara 1" }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateAvalaraIntegrationInput!) {
        createAvalaraIntegration(input: $input) {
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

  before { membership.organization.update!(premium_integrations: ["avalara"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates an avalara integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          code:,
          name:,
          accountId: "account-id1",
          licenseKey: "license-key12",
          connectionId: "this-is-random-uuid"
        }
      }
    )

    result_data = result["data"]["createAvalaraIntegration"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq(code)
      expect(result_data["name"]).to eq(name)
      expect(result_data["licenseKey"]).to eq("••••••••…y12")
      expect(result_data["accountId"]).to eq("account-id1")
      expect(Integrations::AvalaraIntegration.order(:created_at).last.connection_id).to eq("this-is-random-uuid")
    end
  end
end
