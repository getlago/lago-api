# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PlanAppliedRateCards::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, units: 5) }
  let(:input) { {id: plan_rate_card.id, units: 20} }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdatePlanAppliedRateCardInput!) {
        updatePlanAppliedRateCard(input: $input) {
          id
          units
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "updates the units" do
    response = execution["data"]["updatePlanAppliedRateCard"]

    expect(response).to eq("id" => plan_rate_card.id, "units" => 20.0)
    expect(plan_rate_card.reload.units).to eq(20)
  end

  context "when units are cleared" do
    let(:input) { {id: plan_rate_card.id, units: nil} }

    it "removes the units" do
      expect(execution["data"]["updatePlanAppliedRateCard"]["units"]).to be_nil
      expect(plan_rate_card.reload.units).to be_nil
    end
  end

  context "when the plan already has contracts" do
    before { create(:contract, organization:, catalog_plan: plan_rate_card.catalog_plan) }

    it "rejects the change as locked" do
      expect_unprocessable_entity(execution, details: {plan: ["plan_locked"]})

      expect(plan_rate_card.reload.units).to eq(5)
    end
  end

  context "when the rate card belongs to another organization" do
    let(:plan_rate_card) { create(:plan_rate_card, organization: create(:organization), units: 5) }

    it "returns a not found error" do
      expect_not_found(execution)
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
