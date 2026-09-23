# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::OrganizationResolver do
  let(:query) do
    <<~GQL
      query($organizationId: ID!) {
        adminOrganization(organizationId: $organizationId) {
          id name email premiumIntegrations featureFlags createdAt
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, name: "ACME Corp", premium_integrations: ["okta"]) }

  def fetch(organization_id: organization.id, current_user: admin_user)
    execute_graphql(current_user:, query:, variables: {organizationId: organization_id})
  end

  it "returns the organization", :premium do
    result = fetch

    expect(result["data"]["adminOrganization"]).to include(
      "id" => organization.id,
      "name" => "ACME Corp",
      "premiumIntegrations" => ["okta"]
    )
  end

  it "returns nothing when the organization does not exist", :premium do
    result = fetch(organization_id: SecureRandom.uuid)

    expect(result["data"]["adminOrganization"]).to be_nil
  end

  it_behaves_like "a CS admin operation" do
    subject(:response) { fetch(current_user:) }
  end
end
