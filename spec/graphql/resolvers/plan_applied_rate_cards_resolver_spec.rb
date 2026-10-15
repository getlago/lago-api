# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlanAppliedRateCardsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "plans:view" }
  let(:variables) { {planId: catalog_plan.id} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:) }

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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  context "with a standalone product added after a categorized one" do
    let!(:standalone_card) do
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:, product: create(:product, :standalone, organization:)))
    end

    it "lists the standalone product last" do
      ids = execution["data"]["planAppliedRateCards"]["collection"].map { it["id"] }

      expect(ids).to eq([plan_rate_card.id, standalone_card.id])
    end
  end

  context "with filters" do
    let(:variables) { {planId: catalog_plan.id, productType: "fixed", hasRateOverrides: true} }
    let!(:fixed_card) do
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:, product: create(:product, :fixed, organization:)))
    end

    let(:query) do
      <<~GQL
        query($planId: ID, $productType: ProductTypeEnum, $hasRateOverrides: Boolean) {
          planAppliedRateCards(planId: $planId, productType: $productType, hasRateOverrides: $hasRateOverrides) {
            collection { id }
          }
        }
      GQL
    end

    before { create(:rate_phase, organization:, plan_rate_card: fixed_card, rate_override: create(:rate_override, organization:)) }

    it "returns only the matching cards" do
      expect(execution["data"]["planAppliedRateCards"]["collection"].map { it["id"] }).to eq([fixed_card.id])
    end
  end

  it "returns the products assigned to the plan" do
    response = execution["data"]["planAppliedRateCards"]

    expect(response["collection"].map { |i| i["id"] }).to eq([plan_rate_card.id])
    expect(response["metadata"]["totalCount"]).to eq(1)
  end
end
