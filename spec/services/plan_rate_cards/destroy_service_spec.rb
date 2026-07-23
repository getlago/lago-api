# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::DestroyService do
  subject(:result) { described_class.call(plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }

  it "soft deletes the entry" do
    expect(result).to be_success
    expect(result.plan_rate_card).to be_discarded
    expect(plan.reload.plan_rate_cards).to be_empty
  end

  it "discards the entry's phases and their overrides" do
    rate_override = create(:rate_override, organization:)
    phase = create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override:)

    result

    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  context "when the plan has subscriptions" do
    before { create(:subscription, plan:, organization:) }

    it "forbids the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(plan_rate_card.reload).not_to be_discarded
    end
  end

  context "when the entry is missing" do
    let(:plan_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan_rate_card")
    end
  end
end
