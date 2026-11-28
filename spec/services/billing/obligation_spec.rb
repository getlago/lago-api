# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Obligation do
  subject(:ratio) { obligation.proration_ratio_for(segment) }

  let(:terms) { Billing::Terms.new(timing: :arrears, prorated:) }
  let(:prorated) { true }
  let(:timezone) { "UTC" }
  let(:anchor_date) { Date.new(2026, 2, 1) }
  let(:interval_unit) { :month }
  let(:calendar) do
    Billing::Calendar.new(
      anchor_date:, interval: Billing::Interval.new(count: 1, unit: interval_unit), timezone:
    )
  end
  let(:cycle_started_at) { Time.utc(2026, 2, 1) }
  let(:cycle_ended_at) { Time.utc(2026, 3, 1) }
  let(:cycle) do
    Billing::Cycle.new(
      index: 0, started_at: cycle_started_at, ended_at: cycle_ended_at,
      phase: Billing::Phase.default, calendar:
    )
  end
  let(:base_rate) { instance_double(RateCardRate, billing_interval_count: 1, billing_interval_unit: "month") }
  let(:started_at) { cycle_started_at }
  let(:ended_at) { cycle_ended_at }
  let(:segment) { Billing::Segments::Segment.new(started_at:, ended_at:, rate: base_rate) }
  let(:obligation) { described_class.new(cycle:, segments: [segment], billing_at: cycle_ended_at, terms:) }

  describe "#selectable_from?" do
    it "selects coverage ending after the timestamp, even when it has not started" do
      expect(obligation.selectable_from?(cycle_started_at - 1.day)).to be(true)
    end

    it "selects ended coverage at its exact billing timestamp" do
      expect(obligation.selectable_from?(cycle_ended_at)).to be(true)
    end

    it "does not select ended coverage at a different timestamp" do
      expect(obligation.selectable_from?(cycle_ended_at + 1.day)).to be(false)
    end

    it "selects a later billing date even when the timestamp is outside coverage" do
      expect(obligation.selectable_from?(cycle_ended_at + 1.day, after: cycle_started_at)).to be(true)
    end

    it "excludes a billing date equal to the previous billing date" do
      expect(obligation.selectable_from?(cycle_started_at, after: cycle_ended_at)).to be(false)
    end

    context "with delayed termination" do
      let(:termination_at) { Time.utc(2026, 3, 5) }
      let(:terminated_obligation) { obligation.with(termination_billing_at: termination_at) }

      it "does not select coverage already billed at its natural end" do
        expect(terminated_obligation.selectable_from?(cycle_started_at, after: cycle_ended_at)).to be(false)
      end
    end
  end

  describe "#operation_billing_at" do
    let(:termination_at) { Time.utc(2026, 3, 5) }
    let(:terminated_obligation) { obligation.with(termination_billing_at: termination_at) }

    it "keeps the natural date for an initial selection or an already reached date" do
      expect(terminated_obligation.operation_billing_at).to eq(cycle_ended_at)
      expect(terminated_obligation.operation_billing_at(after: cycle_ended_at)).to eq(cycle_ended_at)
      expect(terminated_obligation.operation_billing_at(after: termination_at)).to eq(cycle_ended_at)
    end

    it "uses the termination date for a continuation without changing the obligation" do
      expect(terminated_obligation.operation_billing_at(after: cycle_started_at)).to eq(termination_at)
      expect(terminated_obligation.billing_at).to eq(cycle_ended_at)
      expect(terminated_obligation.cycle).to be(cycle)
      expect(terminated_obligation.segments).to eq([segment])
      expect(terminated_obligation.terms).to be(terms)
    end

    it "supports the original constructor and keeps natural dates without termination metadata" do
      expect(obligation.termination_billing_at).to be_nil
      expect(obligation.operation_billing_at(after: cycle_started_at)).to eq(cycle_ended_at)
    end
  end

  describe "#proration_ratio_for" do
    it "gives a full calendar cycle a ratio of one" do
      expect(ratio).to eq(1.0)
    end

    context "with a partial segment" do
      let(:started_at) { Time.utc(2026, 2, 10) }

      it "measures 19 of February's 28 days" do
        expect(ratio).to eq(19.fdiv(28))
      end
    end

    context "with a partial first cycle" do
      let(:cycle_started_at) { Time.utc(2026, 2, 10) }

      it "keeps the full calendar month as the denominator" do
        expect(ratio).to eq(19.fdiv(28))
      end
    end

    context "with cuts on both sides" do
      let(:started_at) { Time.utc(2026, 2, 8) }
      let(:ended_at) { Time.utc(2026, 2, 22) }

      it "measures 14 of February's 28 days" do
        expect(ratio).to eq(14.fdiv(28))
      end
    end

    context "with midday cuts" do
      let(:started_at) { Time.utc(2026, 2, 8, 12) }
      let(:ended_at) { Time.utc(2026, 2, 22, 12) }

      it "assigns days by local midnights" do
        expect(ratio).to eq(14.fdiv(28))
      end
    end

    context "with no local midnight in the segment" do
      let(:started_at) { Time.utc(2026, 2, 8, 8) }
      let(:ended_at) { Time.utc(2026, 2, 8, 12) }

      it "gives the segment a zero ratio" do
        expect(ratio).to eq(0.0)
      end
    end

    context "with a termination clamp" do
      let(:cycle_ended_at) { Time.utc(2026, 2, 16) }

      it "measures the 15 covered days against the full month" do
        expect(ratio).to eq(15.fdiv(28))
      end
    end

    context "when proration is disabled" do
      let(:prorated) { false }
      let(:started_at) { Time.utc(2026, 2, 10) }
      let(:cycle_ended_at) { Time.utc(2026, 2, 16) }

      it "gives partial coverage a ratio of one" do
        expect(ratio).to eq(1.0)
      end
    end

    context "with a monthly cycle and a weekly base rate" do
      let(:anchor_date) { Date.new(2026, 1, 1) }
      let(:cycle_started_at) { Time.utc(2026, 1, 1) }
      let(:cycle_ended_at) { Time.utc(2026, 2, 1) }
      let(:started_at) { Time.utc(2026, 1, 15) }
      let(:base_rate) { instance_double(RateCardRate, billing_interval_count: 1, billing_interval_unit: "week") }

      it "uses 31 cycle days rather than the base rate's cadence" do
        expect(ratio).to eq(17.fdiv(31))
      end
    end

    context "with a weekly cycle and a monthly base rate" do
      let(:interval_unit) { :week }
      let(:cycle_ended_at) { Time.utc(2026, 2, 8) }
      let(:started_at) { Time.utc(2026, 2, 3) }

      it "uses seven cycle days rather than the base rate's cadence" do
        expect(ratio).to eq(5.fdiv(7))
      end
    end

    context "with a daylight saving transition" do
      let(:timezone) { "America/New_York" }
      let(:zone) { Time.find_zone!(timezone) }
      let(:anchor_date) { Date.new(2026, 3, 1) }
      let(:cycle_started_at) { zone.local(2026, 3, 1) }
      let(:cycle_ended_at) { zone.local(2026, 4, 1) }
      let(:started_at) { zone.local(2026, 3, 8) }
      let(:ended_at) { zone.local(2026, 3, 10) }

      it "measures two local days of the 31-day March cycle" do
        expect(ratio).to eq(2.fdiv(31))
      end
    end
  end
end
