# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::ResolveRatePhasesService do
  subject(:result) { described_class.call(subscription_rate_card:, plan_rate_cards:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_cards) { plan.applied_rate_cards.to_a }
  let(:subscription_rate_card) do
    create(:subscription_rate_card, organization:, customer:, subscription:, rate_card:)
  end

  context "with subscription-level phases" do
    let!(:intro_phase) do
      create(
        :rate_phase,
        :subscription_level,
        organization:,
        subscription_rate_card:,
        position: 1,
        billing_interval_cycle_count: 2
      )
    end
    let!(:standard_phase) do
      create(
        :rate_phase,
        :subscription_level,
        organization:,
        subscription_rate_card:,
        position: 2,
        billing_interval_cycle_count: nil
      )
    end

    it "resolves phases by cycle index" do
      expect(result.rate_phases.rate_phase_for_cycle(0)).to eq(intro_phase)
      expect(result.rate_phases.rate_phase_for_cycle(1)).to eq(intro_phase)
      expect(result.rate_phases.rate_phase_for_cycle(2)).to eq(standard_phase)
    end
  end

  context "without subscription-level phases" do
    let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
    let(:plan_rate_cards) { [plan_rate_card] }
    let!(:plan_phase) do
      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        position: 1,
        billing_interval_cycle_count: nil
      )
    end

    it "falls back to matching plan-level phases" do
      expect(result.rate_phases.rate_phase_for_cycle(0)).to eq(plan_phase)
    end
  end

  context "without matching phases" do
    let(:plan_rate_cards) { [] }

    it "returns no phase" do
      expect(result.rate_phases.rate_phase_for_cycle(0)).to be_nil
    end
  end
end
