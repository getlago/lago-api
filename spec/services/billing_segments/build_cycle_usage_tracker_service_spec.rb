# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::BuildCycleUsageTrackerService do
  subject(:cycle_usage_tracker) do
    described_class.call!(segments: [first, second], obligation:).cycle_usage_tracker
  end

  let(:obligation) { instance_double(Billing::Obligation, coverage_started_at: first.started_at) }

  let(:organization) { build(:organization, feature_flags: ["product_catalog"]) }
  let(:metric) { build(:billable_metric, aggregation_type:, recurring:) }
  let(:aggregation_type) { :latest_agg }
  let(:recurring) { false }
  let(:proration) { false }
  let(:rate_card) { build(:rate_card, product: build(:product, billable_metric: metric), billing_timing:, proration:) }
  let(:billing_timing) { :arrears }
  let(:billing_scope) { :cycle }
  let(:card) { build(:contract_rate_card, rate_card:, billing_scope:) }
  let(:first) { build(:billing_segment, organization:, contract_rate_card: card) }
  let(:second) do
    build(:billing_segment, organization:, contract_rate_card: card, started_at: BillingSegment.exclusive_end(first.ended_at),
      rate_override: build(:rate_override, rate_model: :volume))
  end

  it { is_expected.to be_a(Fees::ChargeService::Trackers::CycleClosingUnits) }

  context "when each segment is billed independently" do
    let(:billing_scope) { :segment }

    it { is_expected.to be_empty }
  end

  context "when the rate card bills in advance" do
    let(:billing_timing) { :advance }

    it { is_expected.to be_empty }
  end

  context "when a sum switches to tiered pricing" do
    let(:aggregation_type) { :sum_agg }

    it { is_expected.to be_a(Fees::ChargeService::Trackers::CycleCarryoverUnits) }

    context "with a recurring balance" do
      let(:recurring) { true }

      it { is_expected.to be_empty }
    end

    context "with proration" do
      let(:proration) { true }

      it { is_expected.to be_empty }
    end
  end

  context "with a non-recurring weighted sum" do
    let(:aggregation_type) { :weighted_sum_agg }

    it "tracks variation rather than tier units" do
      expect(cycle_usage_tracker).to be_a(Fees::ChargeService::Trackers::CycleCarryoverVariation)
      expect(cycle_usage_tracker).to be_carryover_variation
      expect(cycle_usage_tracker.apply_carry_over?).to be(false)
    end

    context "with a recurring balance" do
      let(:recurring) { true }

      it { is_expected.to be_empty }
    end

    context "with segment scope" do
      let(:billing_scope) { :segment }

      it { is_expected.to be_empty }
    end
  end
end
