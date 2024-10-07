# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::DunningCampaigns::Create, type: :graphql do
  let(:required_permission) { "dunning_campaigns:create" }
  let(:membership) { create(:membership) }
  let(:input) do
    {
      name: "Dunning campaign name",
      code: "dunning-campaign-code",
      description: "Dunning campaign description",
      maxAttempts: 3,
      daysBetweenAttempts: 1,
      appliedToOrganization: false
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateDunningCampaignInput!) {
        createDunningCampaign(input: $input) {
          id name code description maxAttempts daysBetweenAttempts appliedToOrganization
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "dunning_campaigns:create"

  it "creates a dunning campaign" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["createDunningCampaign"]).to include(
      "id" => String,
      "name" => "Dunning campaign name",
      "code" => "dunning-campaign-code",
      "description" => "Dunning campaign description",
      "maxAttempts" => 3,
      "daysBetweenAttempts" => 1,
      "appliedToOrganization" => false
    )
  end
end
