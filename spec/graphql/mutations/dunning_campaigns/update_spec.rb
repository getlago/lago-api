# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::DunningCampaigns::Update, type: :graphql do
  let(:required_permission) { "dunning_campaigns:update" }
  let(:organization) { create(:organization, premium_integrations: ["auto_dunning"]) }
  let(:membership) { create(:membership, organization:) }
  let(:dunning_campaign) do
    create(:dunning_campaign, organization:, applied_to_organization: true)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateDunningCampaignInput!) {
        updateDunningCampaign(input: $input) {
          id
          name
          code
          appliedToOrganization
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    dunning_campaign
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "dunning_campaigns:update"

  it "updates a dunning campaign" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: dunning_campaign.id,
          appliedToOrganization: false
        }
      }
    )

    expect(result["data"]["updateDunningCampaign"]).to include(
      "id" => String,
      "name" => dunning_campaign.name,
      "code" => dunning_campaign.code,
      "appliedToOrganization" => false
    )
  end
end
