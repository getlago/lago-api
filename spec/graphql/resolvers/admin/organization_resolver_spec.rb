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

  context "when the license is not premium" do
    it "returns an unauthorized error" do
      expect_graphql_error(result: fetch, message: "unauthorized")
    end
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = fetch(current_user: regular_user)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
