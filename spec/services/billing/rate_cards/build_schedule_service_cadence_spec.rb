# frozen_string_literal: true

require "rails_helper"

# Ported from the previous engine, where these behaviours were covered and passing:
#
#   spec/services/billing_periods/dates/advance_service_spec.rb
#     "with three rates using different billing intervals"
#     "uses the interval active at the cycle start while splitting on effective dates"
#
# The contract has three parts, and the previous engine honoured all three:
#
#   1. the cadence is resolved at the START of each cycle, from the rate in force there
#   2. a rate taking effect INSIDE a cycle splits it into segments — it does not
#      change the cadence of the cycle it lands in
#   3. when the cadence changes, billing re-anchors on the day it changes — LAGO-1766
#      settled this as the ONLY behaviour ("reading B, everything is glued"), which is
#      why the walk re-anchors unconditionally and there is no mode to turn it off
#
# The previous engine stored `period_to` inclusively; this one is half-open, so every
# expectation below is the old one with the end moved to the next instant.
RSpec.describe Billing::RateCards::BuildScheduleService do
  describe "cadence from the rates in force" do
    subject(:schedule) do
      described_class.call(contract_rate_card:).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.utc(2026, 1, 1)) }
    let(:rate_card) { create(:rate_card, :advance, organization:) }

    let(:rates) { rate_card.rates.order(:effective_from) }

    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        billing_anchor_date: Date.new(2026, 1, 1),
        effective_date: Date.new(2026, 1, 1),
        next_billing_at: Time.utc(2026, 1, 1)
      )
    end

    # Monthly, then weekly from Mar 15, then monthly again from May 1. Named by their code,
    # which is what the expectations below read back.
    before do
      create(:rate_card_rate, organization:, rate_card:, code: "monthly",
        effective_from: Time.utc(2026, 1, 1), billing_interval_count: 1, billing_interval_unit: "month")
      create(:rate_card_rate, organization:, rate_card:, code: "weekly",
        effective_from: Time.utc(2026, 3, 15), billing_interval_count: 1, billing_interval_unit: "week")
      create(:rate_card_rate, organization:, rate_card:, code: "monthly_again",
        effective_from: Time.utc(2026, 5, 1), billing_interval_count: 1, billing_interval_unit: "month")
    end

    # Advance segments bill at their start, so keep those opening in the requested window.
    def t(*parts) = Time.utc(*parts).to_fs(:db)

    def billed_windows(from, to)
      schedule.segments_due_by(to)
        .select { |segment| segment.started_at >= from && segment.started_at < to }
        .map { |segment| [segment.started_at.to_fs(:db), segment.ended_at.to_fs(:db), segment.rate.code] }
    end

    it "uses the interval active at the cycle start while splitting on effective dates" do
      expect(billed_windows(Time.utc(2026, 1, 1), Time.utc(2026, 6, 1))).to eq(
        [
          # Monthly, from the only rate in force.
          [t(2026, 1, 1), t(2026, 2, 1), "monthly"],
          [t(2026, 2, 1), t(2026, 3, 1), "monthly"],
          # The weekly rate lands inside the March cycle: it splits it, and March stays monthly.
          [t(2026, 3, 1), t(2026, 3, 15), "monthly"],
          [t(2026, 3, 15), t(2026, 4, 1), "weekly"],
          # April opens with the weekly rate in force, so the cadence turns weekly — and
          # re-anchors on the day it turns, which puts the weeks on the 1st, 8th, 15th...
          [t(2026, 4, 1), t(2026, 4, 8), "weekly"],
          [t(2026, 4, 8), t(2026, 4, 15), "weekly"],
          [t(2026, 4, 15), t(2026, 4, 22), "weekly"],
          [t(2026, 4, 22), t(2026, 4, 29), "weekly"],
          # The monthly rate lands inside the Apr 29 week and splits it, without moving it.
          [t(2026, 4, 29), t(2026, 5, 1), "weekly"],
          [t(2026, 5, 1), t(2026, 5, 6), "monthly_again"],
          # The cadence turns monthly at the next boundary and re-anchors there.
          [t(2026, 5, 6), t(2026, 6, 6), "monthly_again"]
        ]
      )
    end

    # UNRULED, PINNED HERE SO IT IS NOT A SILENT TRAP.
    #
    # Parts 1 and 2 of the contract above mean a slice can be priced by one cadence and
    # measured against another: the cycle's length comes from the rate in force at its start,
    # while the slice after a cut is priced by a rate that may declare a different interval.
    # `proration_ratio` is a share of the CYCLE, so a consumer computing
    # `amount x units x proration_ratio` uses one rate's amount against the other rate's
    # period.
    #
    # The numbers below are what the engine answers today. They are not a decision:
    #
    #   [Mar 15, Apr 1) is 17 days of the 31-day MONTHLY cycle -> 17/31 = 0.548,
    #   and it is priced by the WEEKLY rate. 17 days is 2.43 weeks, so a consumer
    #   charges 0.548 of a week for 2.43 weeks of service - 4.4x too little.
    #
    #   [May 1, May 6) is 5 days of the 7-day WEEKLY cycle -> 5/7 = 0.714, and it is
    #   priced by the MONTHLY rate. 5 days is 5/31 = 0.161 of a month, so a consumer
    #   charges 0.714 of a month - 4.4x too much.
    #
    # AND THERE IS A WRITTEN POLICY THAT SAYS THIS SHOULD NOT BE POSSIBLE.
    #
    # [BE] [Dive-In] 1 - Product, Plan and Rates system (last edited 2026-08-03), "Billing
    # cadence":
    #
    #   "any rate change with a different billing_interval closes the current period at the
    #    effective_from boundary and starts a new period. Mid-period interval mixing is
    #    disallowed, so period length is always derivable from the currently-active rate."
    #
    # and, under the lifecycle of next_billing_at: "Rate change with new interval - close the
    # current period at effective_from, recompute next_billing_at from the new rate's
    # interval starting at that boundary."
    #
    # That is option (D), and its second sentence forbids exactly what the examples below
    # produce. This engine implements neither: the cadence is resolved at the cycle's start
    # (part 1 of the contract at the top of this file) and a mid-cycle rate change splits
    # without moving the boundary (part 2) - both ported from the previous engine, "where
    # these behaviours were covered and passing", so the divergence is inherited, not new.
    #
    # It has not simply been overlooked either. Three later documents reopen it:
    #   - Dive-In 3, open question "Default-phase interval drift": freeze the interval for
    #     the phase, or re-scale the remaining window?
    #   - Dive-In 4, §7 "Interval mismatch": how do cycles map when the sub's billing period
    #     differs from the rate interval?
    #   - [Spec] Plan v2 - Current usage/fees, §7 OQ 1 (2026-08-26, the most recent of the
    #     set): re-anchoring after a cadence-changing phase, "Must be settled before the
    #     window algorithm is implemented."
    # And BIL-464, "Preview across a pending rate or phase transition inside the period",
    # which would have forced the answer, was CANCELED on 2026-08-20.
    #
    # What IS settled, and does not decide this: a SAME-cadence mid-period rate change splits
    # the window and preserves the anchor ([SPEC] Rate cards and Rates, 2026-08-24, scenario
    # 3 and worked ATTEMPT 3; next_billing_at returns to the original boundary) - not (D);
    # and the proration denominator is the period CONTAINING the window (decision #55,
    # measured and confirmed on LAGO-1796), which points at (A). Every application of #55
    # pairs that denominator with the amount charged for that same window, never with a
    # differently-cadenced rate's amount. (B) has no support in Notion, Slack or Linear.
    #
    # So: do not "fix" these numbers to match Dive-In 1 without a ruling, and do not wire a
    # fee computation onto them without reading this. The mixing is latent today - nothing
    # outside app/services/billing reads proration_ratio.
    describe "a cut whose slices are priced on different cadences" do
      # The card above does not prorate, so every slice of a cut cycle reads 1.0 and the
      # question cannot arise on it. It needs a PRORATING card, which is what makes the
      # denominator observable at all.
      let(:rate_card) do
        create(:rate_card, :advance, organization:, proration: true,
          product: create(:product, :fixed, organization:))
      end

      def ratios_by_slice(from, to)
        schedule.segments_due_by(to)
          .select { |segment| segment.started_at >= from && segment.started_at < to }
          .map { |segment| [segment.rate.code, segment.proration_ratio] }
      end

      it "measures the slice against the cycle it sits in, not against its own rate's interval" do
        expect(ratios_by_slice(Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)))
          .to eq([["monthly", 14.fdiv(31)], ["weekly", 17.fdiv(31)]])
      end

      it "does the same in the mirror case, a monthly rate inside a weekly cycle" do
        expect(ratios_by_slice(Time.utc(2026, 4, 29), Time.utc(2026, 5, 6)))
          .to eq([["weekly", 2.fdiv(7)], ["monthly_again", 5.fdiv(7)]])
      end

      # The property that makes it coherent as far as it goes, and the reason B is not a free
      # swap: whatever the slices are priced by, they still add back up to their cycle.
      it "keeps the slices summing to the cycle either way" do
        [[Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)], [Time.utc(2026, 4, 29), Time.utc(2026, 5, 6)]].each do |from, to|
          expect(ratios_by_slice(from, to).sum { |_code, ratio| ratio }).to eq(1.0)
        end
      end
    end

    # The advance segment is already due and still carries the re-anchored end of its cycle.
    it "runs the cadence in force through to the re-anchored boundary" do
      at = Time.utc(2026, 5, 20)
      in_force = schedule.segments_due_by(at).find { |cycle| cycle.ended_at > at }

      expect(in_force.ended_at).to eq(Time.utc(2026, 6, 6))
    end
  end

  # Ported from the previous engine:
  #
  #   spec/services/billing_periods/dates/advance_service_spec.rb
  #     "splits periods at billing boundaries and rate effective dates"
  #   spec/services/billing_periods/dates/arrears_service_spec.rb
  #     "splits shifted periods at billing boundaries and rate effective dates"
  #
  # Both used the same grid — a card starting a month before its anchor, on a weekly cadence,
  # with a second rate of the same cadence taking effect mid-cycle. The two specs differed only in
  # which cycles their range selected, so the grid and the splits are asserted here once.
  describe "a second rate on the same cadence" do
    subject(:schedule) { described_class.call(contract_rate_card:).schedule }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.utc(2026, 1, 1)) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:rates) { rate_card.rates.order(:effective_from) }

    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        billing_anchor_date: Date.new(2026, 8, 3),
        effective_date: Date.new(2026, 7, 1),
        next_billing_at: Time.utc(2026, 7, 1)
      )
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, code: "first",
        effective_from: Time.utc(2026, 7, 1), billing_interval_count: 1, billing_interval_unit: "week")
      create(:rate_card_rate, organization:, rate_card:, code: "second",
        effective_from: Time.utc(2026, 8, 6), billing_interval_count: 1, billing_interval_unit: "week")
    end

    # The anchor is a reference day, not a start date: the weekly grid runs backwards from
    # Aug 3 through Jul 27, Jul 20, Jul 13 and Jul 6, and the card's own start opens the first
    # cycle on Jul 1 rather than on the boundary before it.
    it "puts the cycles on the anchor's grid and clamps the first to the card start" do
      windows = schedule.segments_due_by(Time.utc(2026, 8, 20)).group_by(&:cycle_started_at)
        .map { |started_at, group| [started_at.to_fs(:db), group.last.ended_at.to_fs(:db)] }

      expect(windows).to eq(
        [
          ["2026-07-01 00:00:00", "2026-07-06 00:00:00"],
          ["2026-07-06 00:00:00", "2026-07-13 00:00:00"],
          ["2026-07-13 00:00:00", "2026-07-20 00:00:00"],
          ["2026-07-20 00:00:00", "2026-07-27 00:00:00"],
          ["2026-07-27 00:00:00", "2026-08-03 00:00:00"],
          ["2026-08-03 00:00:00", "2026-08-10 00:00:00"],
          ["2026-08-10 00:00:00", "2026-08-17 00:00:00"]
        ]
      )
    end

    # The second rate carries the same cadence, so it moves nothing: it only cuts the cycle it
    # lands in. This is the case that separates a rate change from a cadence change.
    it "splits the cycle the second rate lands in without moving any boundary" do
      segments = schedule.segments_due_by(Time.utc(2026, 8, 17))
        .select { |segment| segment.started_at >= Time.utc(2026, 8, 3) }
        .map { |segment| [segment.started_at.to_fs(:db), segment.ended_at.to_fs(:db), segment.rate.code] }

      expect(segments).to eq(
        [
          ["2026-08-03 00:00:00", "2026-08-06 00:00:00", "first"],
          ["2026-08-06 00:00:00", "2026-08-10 00:00:00", "second"],
          ["2026-08-10 00:00:00", "2026-08-17 00:00:00", "second"]
        ]
      )
    end
  end

  # Ported from the previous engine:
  #
  #   spec/services/billing_periods/dates_service_spec.rb
  #     "returns periods overlapping the range regardless of billing timing and clamps the
  #      final period"
  #
  # Termination is not a mode here — it is a schedule with an end — so the same walk has to
  # produce the final, clamped cycle and the segments inside it.
  describe "a termination cutting the last cycle short" do
    subject(:schedule) do
      described_class.call(contract_rate_card:, ends_at: terminated_at).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.utc(2026, 1, 1)) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:rates) { rate_card.rates.order(:effective_from) }
    let(:terminated_at) { Time.utc(2026, 8, 17, 12, 34, 56) }

    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        billing_anchor_date: Date.new(2026, 8, 3),
        effective_date: Date.new(2026, 8, 3),
        next_billing_at: Time.utc(2026, 8, 3)
      )
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, code: "first",
        effective_from: Time.utc(2026, 8, 1), billing_interval_count: 1, billing_interval_unit: "week")
      create(:rate_card_rate, organization:, rate_card:, code: "second",
        effective_from: Time.utc(2026, 8, 6), billing_interval_count: 1, billing_interval_unit: "week")
    end

    it "clamps the final cycle to the termination instant, not to the boundary" do
      segments = schedule.segments_due_by(Time.utc(2026, 9, 1))
        .map { |segment| [segment.started_at.to_fs(:db), segment.ended_at.to_fs(:db), segment.rate.code] }

      expect(segments).to eq(
        [
          ["2026-08-03 00:00:00", "2026-08-06 00:00:00", "first"],
          ["2026-08-06 00:00:00", "2026-08-10 00:00:00", "second"],
          ["2026-08-10 00:00:00", "2026-08-17 00:00:00", "second"],
          ["2026-08-17 00:00:00", "2026-08-17 12:34:56", "second"]
        ]
      )
    end

    it "stops producing cycles after the termination" do
      expect(schedule.next_billing_at(after: Time.utc(2027, 1, 1))).to be_nil
    end
  end
end
