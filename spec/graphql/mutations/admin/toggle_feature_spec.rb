# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::ToggleFeature do
  let(:query) do
    <<~GQL
      mutation($input: AdminToggleFeatureInput!) {
        adminToggleFeature(input: $input) {
          id action featureType featureKey organizationId beforeValue afterValue reason
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }

  def toggle(current_user: admin_user, organization_id: organization.id, enabled: true)
    execute_graphql(
      current_user:,
      query:,
      variables: {
        input: {
          organizationId: organization_id,
          featureType: "premium_integration",
          featureKey: "okta",
          enabled:,
          reason: "Enabling okta for the customer POC",
          notifyOrgAdmin: false
        }
      }
    )
  end

  it "toggles the feature and returns the audit log", :premium do
    result = toggle

    log = result["data"]["adminToggleFeature"]
    expect(log["action"]).to eq("toggle_on")
    expect(log["featureType"]).to eq("premium_integration")
    expect(log["featureKey"]).to eq("okta")
    expect(log["organizationId"]).to eq(organization.id)
    expect(log["beforeValue"]).to be(false)
    expect(log["afterValue"]).to be(true)

    expect(organization.reload.premium_integrations).to include("okta")
  end

  context "when the organization does not exist", :premium do
    it "returns a not found error" do
      result = toggle(organization_id: SecureRandom.uuid)

      expect_graphql_error(result:, message: "not_found")
    end
  end

  it_behaves_like "a CS admin operation" do
    subject(:response) { toggle(current_user:) }
  end
end
