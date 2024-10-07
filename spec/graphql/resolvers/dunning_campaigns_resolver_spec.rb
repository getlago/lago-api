# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::DunningCampaignsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        dunningCampaigns(limit: 5) {
          collection { id name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:dunning_campaign) { create(:dunning_campaign, organization:) }

  before { dunning_campaign }

  it "returns a list of dunning campaigns" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    dunning_campaigns_response = result["data"]["dunningCampaigns"]

    aggregate_failures do
      expect(dunning_campaigns_response["collection"].first).to include(
        "id" => dunning_campaign.id,
        "name" => dunning_campaign.name
      )

      expect(dunning_campaigns_response["metadata"]).to include(
        "currentPage" => 1,
        "totalCount" => 1
      )
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end
end
