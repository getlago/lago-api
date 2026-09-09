# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::DestroyService do
  subject(:result) { described_class.call(catalog_plan:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }

  it "soft deletes the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan).to be_discarded
    expect(organization.catalog_plans.kept).to be_empty
  end

  it "tears down the plan's rate cards, phases and overrides" do
    rate_card = create(:rate_card, organization:)
    plan_rate_card = create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
    rate_override = create(:rate_override, organization:)
    phase = create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override:)

    result

    expect(plan_rate_card.reload).to be_discarded
    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  it "enqueues the plan.deleted webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("plan.deleted", catalog_plan)
  end

  context "when the plan is attached to contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "blocks the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(catalog_plan.reload).not_to be_discarded
    end
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
