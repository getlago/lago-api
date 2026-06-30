# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlanRateCardsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {planId: plan.id}
    )
  end

  let(:required_permission) { "plans:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }

  let(:query) do
    <<~GQL
      query($planId: ID) {
        planRateCards(planId: $planId) {
          collection { id ratePhasesCount productItem { id } rateCard { id } }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns the product items assigned to the plan" do
    response = execution["data"]["planRateCards"]

    expect(response["collection"].map { |i| i["id"] }).to eq([plan_rate_card.id])
    expect(response["metadata"]["totalCount"]).to eq(1)
  end
end
