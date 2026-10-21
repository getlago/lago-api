# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlanAppliedRateCardResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: plan_rate_card.id}
    )
  end

  let(:required_permission) { "plans:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, units: 3) }

  let(:query) do
    <<~GQL
      query($id: ID!) {
        planAppliedRateCard(id: $id) {
          id units
          catalogPlan { id name }
          product { id }
          rateCard { id }
          ratePhases { id rateOverride { id } }
          ratePhasesCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns the applied rate card with its plan and rate phases" do
    rate_override = create(:rate_override, organization:)
    rate_phase = create(:rate_phase, organization:, plan_rate_card:, rate_override:)

    expect(execution["data"]["planAppliedRateCard"]).to eq(
      "id" => plan_rate_card.id,
      "units" => 3.0,
      "catalogPlan" => {"id" => catalog_plan.id, "name" => catalog_plan.name},
      "product" => {"id" => plan_rate_card.rate_card.product_id},
      "rateCard" => {"id" => plan_rate_card.rate_card_id},
      "ratePhases" => [{"id" => rate_phase.id, "rateOverride" => {"id" => rate_override.id}}],
      "ratePhasesCount" => 1
    )
  end

  context "when the applied rate card belongs to another organization" do
    let(:plan_rate_card) { create(:plan_rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the applied rate card is discarded" do
    let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, deleted_at: Time.current) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
