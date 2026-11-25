# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Trackers::CycleCarryoverVariation do
  subject(:usage) { described_class.for(segments:, coverage_started_at:) }

  let(:organization) { build(:organization, feature_flags: ["product_catalog"]) }
  let(:start) { Time.utc(2027, 1, 5) }
  let(:coverage_started_at) { start }
  let(:switch) { Time.utc(2027, 1, 16) }
  let(:first) { build(:billing_segment, organization:, started_at: start, ended_at: BillingSegment.inclusive_end(switch)) }
  let(:second) do
    build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: switch,
      rate_override: build(:rate_override, rate_model: "standard"), ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 1)))
  end
  let(:segments) { [first, second] }
  let(:first_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: first) }
  let(:second_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: second) }
  let(:local_usage) do
    BillableMetrics::Aggregations::BaseService::Result.new.tap do |result|
      result.aggregation = 15
      result.variation = BigDecimal("31.5")
    end.freeze
  end

  it "carries raw variation between standard rates without shifting pricing tiers" do
    expect(usage.carryover_variation?).to be(true)
    expect(usage.apply_carry_over?).to be(false)
    expect(usage.opening_variations(metered_item: first_item)).to eq({})
    usage.each_opening_balance(metered_item: first_item, groups: [local_usage])

    expect(usage.opening_variations(metered_item: second_item)).to eq(nil => BigDecimal("31.5"))
    expect { |block| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &block) }
      .to yield_with_args(local_usage, BigDecimal("31.5"))
    expect(usage).to be_empty
  end

  context "with a single segment" do
    let(:segments) { [first] }

    it "provides an explicit empty opening rather than recurring history" do
      expect(usage).not_to be_empty
      expect(usage.carryover_variation?).to be(true)
      expect(usage.opening_variations(metered_item: first_item)).to eq({})
    end
  end

  context "when pricing group keys change" do
    let(:first) { super().tap { it.rate_properties = {"pricing_group_keys" => ["region"]} } }

    it "clears the old balance before both reading and finishing the final segment" do
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])

      expect(usage.opening_variations(metered_item: second_item)).to eq({})
      expect { |block| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &block) }
        .to yield_with_args(local_usage, 0)
    end
  end

  context "when a segment has no observations" do
    let(:third) do
      build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card,
        started_at: BillingSegment.exclusive_end(second.ended_at))
    end
    let(:third_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: third) }
    let(:segments) { [first, second, third] }

    it "retains the quantity for the next segment" do
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])
      usage.each_opening_balance(metered_item: second_item, groups: [])

      expect(usage.opening_variations(metered_item: third_item)).to eq(nil => BigDecimal("31.5"))
    end
  end
end
