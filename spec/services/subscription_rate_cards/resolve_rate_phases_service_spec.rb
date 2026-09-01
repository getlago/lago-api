# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::ResolveRatePhasesService do
  subject(:result) { described_class.call(subscription_rate_card:, plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { nil }
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

    it "returns the card's phases in position order" do
      expect(result.rate_phases).to eq([intro_phase, standard_phase])
    end
  end

  context "without subscription-level phases" do
    let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
    let!(:plan_phase) do
      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        position: 1,
        billing_interval_cycle_count: nil
      )
    end

    it "falls back to the plan entry's phases" do
      expect(result.rate_phases).to eq([plan_phase])
    end
  end

  # Neither the card nor a plan entry carries phases, and a card off a plan has no entry
  # to fall back to at all.
  context "without any phases" do
    it "returns none" do
      expect(result.rate_phases).to be_empty
    end
  end
end
