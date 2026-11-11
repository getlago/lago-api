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

  describe "#planned_operations_for_cycle" do
    subject(:planned_operations) do
      schedule.planned_operations_for_cycle(schedule.cycle_at(starts_at), action_type:)
    end

    let(:starts_at) { Time.utc(2026, 2, 1) }
    let(:action_type) { "renew_fixed_advance" }
    let(:anchor_date) { Date.new(2026, 2, 1) }
    let(:rates) { [card_rate(Time.utc(2026, 1, 1)), card_rate(Time.utc(2026, 2, 15))] }

    context "when billing in advance" do
      let(:timing) { :advance }

      it "keeps each separately due slice in its own operation" do
        expect(planned_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15)])
        expect(planned_operations.map { it.billable_segments.map(&:started_at) }).to eq([
          [Time.utc(2026, 2, 1)], [Time.utc(2026, 2, 15)]
        ])
        expect(planned_operations.map(&:cycle_started_at).uniq).to eq([Time.utc(2026, 2, 1)])
        expect(planned_operations.map { it.billable_segments.sole.proration_ratio }).to eq([14.fdiv(28), 14.fdiv(28)])
      end
    end

    context "when billing in arrears" do
      let(:timing) { :arrears }
      let(:action_type) { "close_fixed_arrears" }

      it "releases each slice at its own end" do
        expect(planned_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 15), Time.utc(2026, 3, 1)])
        expect(planned_operations.map { it.billable_segments.sole.started_at }).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15)])
      end
    end

    context "when grouping paid fee recovery" do
      let(:timing) { :advance }
      let(:action_type) { "regroup_paid_fees" }

      it "groups recovered fees by their service end" do
        expect(planned_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 15), Time.utc(2026, 3, 1)])
      end
    end
  end
end
