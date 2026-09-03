# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlanAppliedRateCardsResolver do
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
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
  let(:organization) { membership.organization }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }
  let(:query) do
    <<~GQL
      query($planId: ID) {
        planAppliedRateCards(planId: $planId) {
          collection { id ratePhasesCount product { id } rateCard { id } }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:plan) { create_default(:plan, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns the products assigned to the plan" do
    response = execution["data"]["planAppliedRateCards"]

    expect(response["collection"].map { |i| i["id"] }).to eq([plan_rate_card.id])
    expect(response["metadata"]["totalCount"]).to eq(1)
  end
end
