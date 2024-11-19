# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::DunningCampaignResolver, type: :graphql do
  let(:required_permission) { "dunning_campaigns:view" }
  let(:query) do
    <<~GQL
      query($dunningCampaignId: ID!) {
        dunningCampaign(id: $dunningCampaignId) {
          id
          appliedToOrganization
          code
          daysBetweenAttempts
          description
          maxAttempts
          name
          createdAt
          updatedAt

          thresholds { amountCents, currency }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:dunning_campaign) { create(:dunning_campaign, organization:) }
  let(:dunning_campaign_threshold) { create(:dunning_campaign_threshold, dunning_campaign:) }

  before do
    dunning_campaign
    dunning_campaign_threshold
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "dunning_campaigns:view"

  it "returns a single dunning campaign", :aggregate_failures do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {dunningCampaignId: dunning_campaign.id}
    )

    dunning_campaign_response = result["data"]["dunningCampaign"]

    expect(dunning_campaign_response).to include(
      {
        "id" => dunning_campaign.id,
        "appliedToOrganization" => dunning_campaign.applied_to_organization,
        "code" => dunning_campaign.code,
        "daysBetweenAttempts" => dunning_campaign.days_between_attempts,
        "description" => dunning_campaign.description,
        "maxAttempts" => dunning_campaign.max_attempts,
        "name" => dunning_campaign.name,
        "thresholds" => [
          {
            "amountCents" => dunning_campaign_threshold.amount_cents.to_s,
            "currency" => dunning_campaign_threshold.currency
          }
        ]
      }
    )
  end

  context "when dunning campaign is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {dunningCampaignId: "unknown"}
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        permissions: required_permission,
        query:,
        variables: {dunningCampaignId: dunning_campaign.id}
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permission,
        query:,
        variables: {dunningCampaignId: dunning_campaign.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end
end
