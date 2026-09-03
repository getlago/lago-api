# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::CreateOrganization do
  let(:query) do
    <<~GQL
      mutation($input: AdminCreateOrganizationInput!) {
        adminCreateOrganization(input: $input) {
          inviteUrl
          organization { id name premiumIntegrations featureFlags }
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }

  before { create(:role, :admin) }

  def create_organization(current_user: admin_user, feature_flags: ["order_forms"])
    execute_graphql(
      current_user:,
      query:,
      variables: {
        input: {
          name: "Hooli Inc",
          ownerEmail: "owner@hooli.test",
          premiumIntegrations: ["okta"],
          featureFlags: feature_flags,
          reason: "New enterprise customer onboarding"
        }
      }
    )
  end

  it "creates the organization with its features and returns the invite url", :premium do
    result = create_organization

    payload = result["data"]["adminCreateOrganization"]
    expect(payload["organization"]["name"]).to eq("Hooli Inc")
    expect(payload["organization"]["premiumIntegrations"]).to eq(["okta"])
    expect(payload["organization"]["featureFlags"]).to eq(["order_forms"])
    expect(payload["inviteUrl"]).to be_present

    organization = Organization.find(payload["organization"]["id"])
    expect(CsAdminAuditLog.where(organization:).pluck(:feature_key))
      .to match_array(%w[organization okta order_forms])
  end

  context "when a feature flag is unknown", :premium do
    it "returns a validation error" do
      result = create_organization(feature_flags: ["not_a_real_flag"])

      expect_graphql_error(result:, message: "unprocessable_entity")
      expect(Organization.find_by(name: "Hooli Inc")).to be_nil
    end
  end

  context "when the license is not premium" do
    it "returns an unauthorized error" do
      result = create_organization

      expect_graphql_error(result:, message: "unauthorized")
      expect(Organization.find_by(name: "Hooli Inc")).to be_nil
    end
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = create_organization(current_user: regular_user)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
