# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PlanAppliedRateCards::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {planId: plan.id, rateCardCode: rate_card.code, units: 10.0}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, :product_catalog, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePlanAppliedRateCardInput!) {
        createPlanAppliedRateCard(input: $input) {
          id
          units
          ratePhasesCount
          product { id }
          rateCard { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "assigns the product to the plan with a default rate phase" do
    response = execution["data"]["createPlanAppliedRateCard"]

    expect(response["product"]["id"]).to eq(rate_card.product.id)
    expect(response["rateCard"]["id"]).to eq(rate_card.id)
    expect(response["units"]).to eq(10.0)
    expect(response["ratePhasesCount"]).to eq(1)
  end
end
