# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Trackers::CycleCarryoverUnits do
  subject(:usage) { described_class.for(segments:, coverage_started_at:) }

  let(:organization) { build(:organization, feature_flags: ["product_catalog"]) }
  let(:start) { Time.utc(2027, 1, 5) }
  let(:coverage_started_at) { start }
  let(:switch) { Time.utc(2027, 1, 16) }
  let(:first) { build(:billing_segment, organization:, started_at: start, ended_at: BillingSegment.inclusive_end(switch)) }
  let(:second) do
    build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: switch,
      rate_override: build(:rate_override, rate_model: "volume"), ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 1)))
  end
  let(:segments) { [first, second] }
  let(:first_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: first) }
  let(:second_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: second) }
  let(:local_usage) do
    BillableMetrics::Aggregations::BaseService::Result.new.tap do |result|
      result.aggregation = 10
    end.freeze
  end

  it "carries the previous segment's units into a different model" do
    expect(usage.carryover_variation?).to be(false)
    expect { |b| usage.each_opening_balance(metered_item: first_item, groups: [local_usage], &b) }.not_to yield_control
    expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.to yield_with_args(local_usage, 10)
  end

  context "when a standard rate follows the last tiered switch" do
    let(:third) do
      build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card,
        started_at: BillingSegment.exclusive_end(second.ended_at))
    end
    let(:third_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: third) }
    let(:segments) { [first, second, third] }
    let(:unread_groups) { Enumerator.new { raise "unexpected group traversal" } }

    it "delivers the final opening balance and skips subsequent groups" do
      expect(usage.apply_closing_values?).to be(false)
      expect(usage.apply_carry_over?).to be(true)
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])
      expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.to yield_with_args(local_usage, 10)
      expect(usage).to be_empty
      expect(usage.apply_carry_over?).to be(false)
      usage.each_opening_balance(metered_item: third_item, groups: unread_groups)
    end
  end

  it "advances past a bypassed segment without carrying any of its units" do
    usage.each_opening_balance(metered_item: first_item, groups: [])
    expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.to yield_with_args(local_usage, 0)
  end

  context "with a single segment" do
    let(:segments) { [first] }

    it "has no closing values or carryover to apply" do
      expect(usage).to be_empty
      expect(usage.apply_closing_values?(groups: [local_usage])).to be(false)
      expect(usage.apply_carry_over?).to be(false)
    end
  end

  context "when the new price is standard" do
    let(:second) { build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: switch) }

    it { is_expected.to be_empty }
  end

  context "when the grouping changes at the switch" do
    let(:first) { build(:billing_segment, organization:, rate_properties: {"pricing_group_keys" => ["region"]}) }

    it { is_expected.to be_empty }
  end

  context "when an ungrouped rate returns after an empty grouped segment" do
    let(:coverage_started_at) { start - 2.weeks }
    let(:prior) do
      build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: coverage_started_at,
        ended_at: BillingSegment.inclusive_end(start - 1.week))
    end
    let(:grouped) do
      build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: start - 1.week,
        ended_at: BillingSegment.inclusive_end(start), rate_properties: {"pricing_group_keys" => ["region"]})
    end
    let(:segments) { [prior, grouped, first, second] }

    it "only carries units accumulated since the last grouping change" do
      usage.each_opening_balance(metered_item: Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: prior), groups: [local_usage])
      usage.each_opening_balance(metered_item: Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: grouped), groups: [])
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])

      expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.to yield_with_args(local_usage, 10)
    end
  end

  context "when an earlier price edit precedes the switch" do
    let(:coverage_started_at) { start - 1.day }
    let(:earlier) do
      build(:billing_segment, organization:, contract_rate_card: first.contract_rate_card, started_at: coverage_started_at,
        ended_at: BillingSegment.inclusive_end(start))
    end
    let(:segments) { [earlier, first, second] }
    let(:earlier_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: earlier) }

    it "carries units from both preceding segments" do
      usage.each_opening_balance(metered_item: earlier_item, groups: [local_usage])
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])
      expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.to yield_with_args(local_usage, 10 + 10)
    end
  end

  context "when the saved coverage starts before the first available segment" do
    let(:coverage_started_at) { start - 1.day }

    it "does not use an incomplete opening balance" do
      usage.each_opening_balance(metered_item: first_item, groups: [local_usage])
      expect { |b| usage.each_opening_balance(metered_item: second_item, groups: [local_usage], &b) }.not_to yield_control
    end
  end
end
