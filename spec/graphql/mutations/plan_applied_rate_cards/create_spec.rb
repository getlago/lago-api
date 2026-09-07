# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PlanAppliedRateCards::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:input) { {planId: plan.id, rateCardCode: rate_card.code, units: 10.0} }

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

  context "with nested rate phases" do
    let(:input) do
      {
        planId: plan.id,
        rateCardCode: rate_card.code,
        ratePhases: [
          {code: "launch", position: 1, name: "Launch", billingIntervalCycleCount: 3},
          {code: "standard", position: 2, name: "Standard"}
        ]
      }
    end

    it "creates the entry with the provided phases" do
      result_data = execution["data"]["createPlanAppliedRateCard"]

      expect(result_data["ratePhasesCount"]).to eq(2)
    end

    context "when the list is explicitly empty" do
      let(:input) { {planId: plan.id, rateCardCode: rate_card.code, ratePhases: []} }

      it "returns an error" do
        expect_graphql_error(result: execution, message: :unprocessable_entity)
      end
    end
  end
end
