# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Trackers::CycleClosingUnits do
  subject(:tracker) { described_class.new(maximum: false) }

  let(:start) { Time.zone.local(2027, 1, 1) }
  let(:switch) { start + 2.weeks }
  let(:second_start) { switch }
  let(:first) { build(:billing_segment, cycle_started_at: start, ended_at: BillingSegment.inclusive_end(switch)) }
  let(:second) { build(:billing_segment, contract_rate_card: first.contract_rate_card, cycle_started_at: start, started_at: second_start) }
  let(:first_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: first) }
  let(:second_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: second) }
  let(:zero_observation) do
    BillableMetrics::Aggregations::BaseService::Result.new.tap do |group|
      group.aggregation = 0
      group.count = 1
    end.freeze
  end

  it "retains an observed zero through a contiguous eventless segment" do
    expect(tracker.apply_closing_values?).to be(false)
    expect(tracker.apply_carry_over?).to be(false)
    expect(tracker.apply_closing_values?(groups: [zero_observation])).to be(true)

    expect { |block| tracker.each_closing_value(metered_item: first_item, groups: [zero_observation], &block) }
      .to yield_with_args(zero_observation, 0, nil)

    expect(tracker.apply_closing_values?).to be(true)
    expect { |block| tracker.each_closing_value(metered_item: second_item, groups: [], &block) }
      .to yield_with_args(nil, 0, nil)
  end

  context "when coverage resumes after a gap" do
    let(:second_start) { switch + 1.day }

    it "does not carry the observed zero into the eventless segment" do
      expect { |block| tracker.each_closing_value(metered_item: first_item, groups: [zero_observation], &block) }
        .to yield_with_args(zero_observation, 0, nil)
      expect { |block| tracker.each_closing_value(metered_item: second_item, groups: [], &block) }
        .not_to yield_control
    end
  end
end
