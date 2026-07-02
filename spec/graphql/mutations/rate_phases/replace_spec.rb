# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RatePhases::Replace do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {planProductItemId: plan_product_item.id, ratePhases: phases}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, rate_card:) }

  let(:phases) do
    [
      {position: 1, name: "trial", billingIntervalCycleCount: 3},
      {position: 2, name: "standard", billingIntervalCycleCount: nil}
    ]
  end

  let(:mutation) do
    <<~GQL
      mutation($input: ReplaceRatePhasesInput!) {
        replaceRatePhases(input: $input) {
          id
          position
          name
          billingIntervalCycleCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "replaces the ordered phase sequence" do
    response = execution["data"]["replaceRatePhases"]

    expect(response.map { |phase| phase["position"] }).to eq([1, 2])
    expect(response.map { |phase| phase["name"] }).to eq(%w[trial standard])
    expect(response.map { |phase| phase["billingIntervalCycleCount"] }).to eq([3, nil])
  end
end
