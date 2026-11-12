# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule do
  subject(:schedule) do
    described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:, ends_at:)
  end

  let(:anchor_date) { Date.new(2022, 1, 1) }
  let(:phases) { [phase(cycle_count: nil, every: 1, unit: :month)] }
  let(:rates) { [card_rate(Time.utc(2000, 1, 1))] }
  let(:prorated) { true }
  let(:timezone) { "UTC" }
  let(:starts_at) { Time.utc(2022, 1, 15) }
  let(:timing) { :arrears }
  let(:ends_at) { nil }
  let(:terms) { Billing::Terms.new(timing:, prorated:) }

  def card_rate(effective_from, count = 1, unit = :month)
    Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit)
      .new(effective_from, count, unit)
  end

  def phase(cycle_count:, every:, unit:, code: "standard")
    Billing::Phase.new(
      code:,
      billing_interval_cycle_count: cycle_count,
      rate_override: Struct.new(:billing_interval_count, :billing_interval_unit).new(every, unit)
    )
  end

  describe "#cycle_at and #next_billable_cycle" do
    it "resolves the target cycle with an exclusive end and advances by cycle, not billing time" do
      cycle = schedule.cycle_at(Time.utc(2022, 2, 1))
      next_cycle = schedule.next_billable_cycle(after_cycle_started_at: cycle.started_at)

      expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2022, 2, 1), Time.utc(2022, 3, 1)])
      expect(next_cycle.started_at).to eq(Time.utc(2022, 3, 1))
    end

    context "when pricing starts in a future cycle" do
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "skips unpriced cycles and returns the first eligible one" do
        first_priced = schedule.next_billable_cycle(after_cycle_started_at: starts_at - 1.second)

        expect([first_priced.started_at, first_priced.ended_at]).to eq([Time.utc(2022, 5, 1), Time.utc(2022, 6, 1)])
      end
    end
  end

  describe "billing dates of a cycle split by a price change" do
    let(:cycle) { schedule.cycle_at(starts_at) }
    let(:starts_at) { Time.utc(2026, 2, 1) }
    let(:anchor_date) { Date.new(2026, 2, 1) }
    let(:rates) { [card_rate(Time.utc(2026, 1, 1)), card_rate(Time.utc(2026, 2, 15))] }

    context "when billing in advance" do
      let(:timing) { :advance }
      let(:action_type) { "renew_fixed_advance" }

      it "bills at the cycle start and releases the later slice at the price change" do
        expect(schedule.billing_dates_for_cycle(cycle, action_type:)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15)])
      end
    end

    context "when billing in arrears" do
      let(:timing) { :arrears }
      let(:action_type) { "close_fixed_arrears" }

      it "closes at the cycle end and releases the earlier slice at the price change" do
        expect(schedule.billing_dates_for_cycle(cycle, action_type:)).to eq([Time.utc(2026, 2, 15), Time.utc(2026, 3, 1)])
      end
    end

    context "when grouping paid fee recovery" do
      let(:timing) { :advance }
      let(:action_type) { "regroup_paid_fees" }

      it "follows each slice's service end rather than its advance billing date" do
        expect(schedule.billable_segments_for_cycle(cycle).map { schedule.due_at(it, action_type:) })
          .to eq([Time.utc(2026, 2, 15), Time.utc(2026, 3, 1)])
      end
    end

    context "when the cycle has a single price" do
      let(:rates) { [card_rate(Time.utc(2026, 1, 1))] }
      let(:action_type) { "close_fixed_arrears" }

      it "has one billing date" do
        expect(schedule.billing_dates_for_cycle(cycle, action_type:)).to eq([Time.utc(2026, 3, 1)])
      end
    end
  end

  describe "#next_planned_operation" do
    let(:cycle) { schedule.cycle_at(starts_at) }
    let(:starts_at) { Time.utc(2026, 2, 1) }
    let(:anchor_date) { Date.new(2026, 2, 1) }
    let(:rates) { [card_rate(Time.utc(2026, 1, 1)), card_rate(Time.utc(2026, 2, 15))] }
    let(:timing) { :arrears }
    let(:action_type) { "close_fixed_arrears" }

    it "starts with the first billing date of the cycle" do
      expect(schedule.next_planned_operation(cycle, action_type:))
        .to eq(described_class::PlannedOperation.new(cycle_started_at: starts_at, billing_at: Time.utc(2026, 2, 15)))
    end

    it "moves to the next billing date of the same cycle" do
      expect(schedule.next_planned_operation(cycle, action_type:, after: Time.utc(2026, 2, 15)))
        .to eq(described_class::PlannedOperation.new(cycle_started_at: starts_at, billing_at: Time.utc(2026, 3, 1)))
    end

    it "moves to the next cycle after the last billing date" do
      expect(schedule.next_planned_operation(cycle, action_type:, after: Time.utc(2026, 3, 1)))
        .to eq(described_class::PlannedOperation.new(cycle_started_at: Time.utc(2026, 3, 1), billing_at: Time.utc(2026, 4, 1)))
    end

    context "when the contract ends with the cycle" do
      let(:ends_at) { Time.utc(2026, 3, 1) }

      it "plans nothing" do
        expect(schedule.next_planned_operation(cycle, action_type:, after: Time.utc(2026, 3, 1))).to be_nil
      end
    end
  end
end
