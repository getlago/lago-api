# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PlanAppliedRateCards::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: plan_rate_card.id}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyPlanAppliedRateCardInput!) {
        destroyPlanAppliedRateCard(input: $input) {
          id
          ratePhasesCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "removes the rate card along with its phases" do
    response = execution["data"]["destroyPlanAppliedRateCard"]

    expect(response["id"]).to eq(plan_rate_card.id)
    expect(response["ratePhasesCount"]).to eq(0)
    expect(plan_rate_card.reload).to be_discarded
    expect(rate_phase.reload).to be_discarded
  end

  context "when the plan already has contracts" do
    before { create(:contract, organization:, catalog_plan: plan_rate_card.catalog_plan) }

    it "rejects the removal as locked" do
      expect_unprocessable_entity(execution, details: {plan: ["plan_locked"]})

      expect(plan_rate_card.reload).not_to be_discarded
    end
  end

  context "when the rate card belongs to another organization" do
    let(:plan_rate_card) { create(:plan_rate_card, organization: create(:organization)) }
    let!(:rate_phase) { nil }

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
