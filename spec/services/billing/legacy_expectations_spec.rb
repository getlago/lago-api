# frozen_string_literal: true

require "rails_helper"

# 18 of the 19 examples the old engine carried, re-aimed at the new one.
#
# Source (left untouched — the old engine is still live at five call sites):
#   spec/services/billing_periods/dates_service_spec.rb          (9, one dropped -> 8)
#   spec/services/billing_periods/dates/advance_service_spec.rb  (5)
#   spec/services/billing_periods/dates/arrears_service_spec.rb  (5)
#
# Every example below keeps the original's name, inputs and intent so the two files can be
# read side by side. What changed is only the shape of the question — except where a comment
# says otherwise, and there are two such places, both caused by the same thing.
#
# THE FIXED ANCHOR MODE IS GONE
#
# `AnchorPolicy::Fixed` was withdrawn per LAGO-1766, which ruled against a second anchor mode
# for v1. `realign_billing_anchor: false` therefore has no successor, and everything the old
# engine did under it is unreachable. One example asserted that behaviour and nothing else, so
# it is DELETED and a comment stands where it was. Two more (the "three rates" pair) ran under
# it only incidentally: their windows are re-derived under Realigning, and the comment on each
# says which pinned values moved and why.
#
# HOW THE OLD CALL TRANSLATES
#
#   old                                          new
#   ------------------------------------------   --------------------------------------------
#   DatesService.from_subscription_rate_card     BuildScheduleService.call!(...).schedule
#   Options#timezone                             customer.applicable_timezone
#   Options#realign_billing_anchor: true         anchor_policy: AnchorPolicy::Realigning
#   Options#realign_billing_anchor: false        NOTHING. The fixed-anchor mode was withdrawn
#                                                (LAGO-1766); only Realigning ships, so the
#                                                option has no successor at all
#   Options#termination: true                    build with ends_at:, then segments_overlapping
#   Options#exclude_out_of_range: true           see #billed_in below
#   Options#exclude_out_of_range: false          advance  => segments_overlapping(range)
#                                                arrears  => segments_due_by(range_end)
#   Period#period_from / #period_to (INCLUSIVE)  #started_at / #ended_at (HALF-OPEN)
#   Period#next_billing_at (carried per period)  gone; it was the cycle's own end
#   Period#cycle_index                           BillableSegment#cycle_index
#   Period#rate_phase                            NOT exposed; a phase is observable only
#                                                through BillableSegment#rate_override
#   result.next_billing_at                       schedule.next_billing_at(after: range_end)
#
# WHY `exclude_out_of_range: false` MAPS TO TWO DIFFERENT METHODS
#
# The option only ever gated `include_period?`. `cycle_due?` ran regardless, and it is not
# the same test in the two timings (CHARACTERIZATION R45/R46):
#   advance  `period_from <= range_end && cycle_end > range_begin`  — a plain overlap
#   arrears  `cycle_close <= range_end && at(idx + 2) > range_begin` — a due-by test
# So "show me the whole timeline" showed an overlap for advance and a due list for arrears;
# the in-progress arrears cycle was never in it (S7). The port asks each timing the question
# the old code actually answered.
#
# THE RANGE LOWER BOUND
#
# `exclude_out_of_range: true` is the conjunction of both filters, and for both timings that
# conjunction is exactly
#
#     segments_due_by(range_end).select { it.ended_at > range_begin }
#
# (`period_to >= range_begin` on an inclusive end is `ended_at > range_begin` on a half-open
# one, to the microsecond.) The new engine keeps only the first half on purpose: the lower
# bound was the caller's already-billed watermark, and a cycle closing exactly on it being
# dropped is the revenue bug of BLIND_DESIGN 2.2 / CHARACTERIZATION S3. `#billed_in`
# reproduces the old conjunction here, in the spec, so a ported example reads next to its
# original. It is never what a call site does.
#
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Billing::BuildScheduleService do
  # rubocop:enable RSpec/SpecFilePathFormat
  def t(value)
    Time.zone.parse(value)
  end

  # The old engine snapped the range to whole UTC days before filtering (R48).
  def day_start(value)
    t(value.to_s).beginning_of_day
  end

  def day_end(value)
    t(value.to_s).end_of_day
  end

  def billed_in(schedule, from:, to:)
    schedule.segments_due_by(to).select { it.ended_at > from }
  end

  def windows(segments)
    segments.map { [it.started_at, it.ended_at] }
  end

  describe "BillingPeriods::DatesService" do
    subject(:schedule) do
      described_class.call!(subscription_rate_card:, plan_rate_card:, ends_at:, anchor_policy:).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) do
      create(
        :subscription,
        customer:,
        organization:,
        plan:,
        started_at: t("2026-08-03"),
        activated_at: t("2026-08-03"),
        subscription_at: t("2026-08-03")
      )
    end
    let(:rate_card) { create(:rate_card, organization:) }
    let(:anchor_policy) { Billing::AnchorPolicy::Realigning }
    let(:plan_rate_card) { nil }
    let(:ends_at) { nil }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-08-03"),
        started_at: t("2026-08-03"),
        next_billing_at: t("2026-08-03")
      )
    end
    let(:range_begin) { day_start("2026-08-05") }
    let(:range_end) { day_end("2026-08-17") }
    let!(:intro_phase) do
      create(
        :rate_phase,
        :subscription_level,
        organization:,
        subscription_rate_card:,
        position: 1,
        billing_interval_cycle_count: 1
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

    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: t("2026-08-01"),
        billing_interval_unit: "week"
      )
    end
    let(:second_rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        code: "rate_r1_v2",
        effective_from: t("2026-08-06"),
        billing_interval_unit: "week"
      )
    end

    before do
      rate_card_rate
      second_rate_card_rate
    end

    # UNPORTABLE. `Options` has no successor: its four fields went to four different places
    # (see the table at the top of this file). Only one of them is still a defaulted argument
    # at all — the anchor mode, which every call site leaves alone.
    #
    # An anchor mode is invisible until the cadence changes, so unlike its original this
    # example needs inputs: a one-cycle weekly phase in front of a monthly rate. Cycle 1 then
    # closes on 2026-09-10 — a month from where the cadence changed, which is what Realigning
    # means — whether the argument is omitted or passed. The second half of this example used
    # to assert 2026-09-03 for `Fixed`, a month from the original anchor; `Fixed` was withdrawn
    # per LAGO-1766, so what is left is that omitting the argument still gets Realigning.
    describe "::Options" do
      let(:rate_override) do
        create(:rate_override, organization:, billing_interval_count: 1, billing_interval_unit: "week")
      end

      before do
        rate_card.rates.find_each { |rate| rate.update!(billing_interval_unit: "month") }
        intro_phase.update!(billing_interval_cycle_count: 1, rate_override:)
      end

      def second_cycle_end(built)
        built.segments_due_by(day_end("2026-12-31")).find { it.cycle_index == 1 }.ended_at
      end

      it "provides the default date-generation options" do
        expect(second_cycle_end(described_class.call!(subscription_rate_card:).schedule))
          .to eq(t("2026-09-10"))
        expect(second_cycle_end(schedule)).to eq(t("2026-09-10"))
      end
    end

    # HOLDS. Same three windows, same indices, same rates.
    it "keeps the same cycle window when a rate effective date splits a cycle" do
      segments = billed_in(schedule, from: range_begin, to: range_end)

      expect(segments.map(&:started_at)).to eq([t("2026-08-03"), t("2026-08-06"), t("2026-08-10")])
      expect(segments.map(&:cycle_index)).to eq([0, 0, 1])
      expect(segments.map(&:rate)).to eq([rate_card_rate, second_rate_card_rate, second_rate_card_rate])
      # The original also asserted rate_phase == [intro, intro, standard]. A BillableSegment
      # carries the phase's override, not the phase; neither phase here has one, so the only
      # trace of them the engine exposes is nil on both sides of the boundary.
      expect(segments.map(&:rate_override)).to eq([nil, nil, nil])
    end

    context "with a terminal phase" do
      let(:range_begin) { day_start("2026-08-24") }
      let(:range_end) { day_end("2026-09-07") }

      # HOLDS. The unbounded phase keeps owning cycles 3 and 4.
      it "keeps using the nil cycle-count phase for later cycles" do
        segments = billed_in(schedule, from: range_begin, to: range_end)

        expect(segments.map(&:cycle_index)).to eq([3, 4])
        expect(segments.map(&:rate_override)).to eq([nil, nil])
      end
    end

    context "with an invalid billing timing" do
      before do
        allow(subscription_rate_card.rate_card).to receive(:billing_timing).and_return("invalid")
      end

      # HOLDS. Still an ArgumentError, raised by Billing::Terms instead of by the service
      # picking a subclass. The message changed.
      it "raises an exception" do
        expect { schedule }.to raise_error(ArgumentError, /unknown billing timing :invalid/)
      end
    end

    context "with termination mode" do
      let(:range_begin) { t("2026-08-05") }
      let(:range_end) { t("2026-08-17 12:34:56") }
      let(:ends_at) { t("2026-08-17 12:34:56") }

      # SHAPE ONLY. Every inclusive end moves up by 1 microsecond to the next window's start.
      # The clamped final window is the exception: the old engine already ended it at the raw
      # termination instant (R49), so that number is unchanged.
      it "returns periods overlapping the range regardless of billing timing and clamps the final period" do
        expect(windows(schedule.segments_overlapping(range_begin..range_end))).to eq(
          [
            [t("2026-08-03"), t("2026-08-06")],
            [t("2026-08-06"), t("2026-08-10")],
            [t("2026-08-10"), t("2026-08-17")],
            [t("2026-08-17"), t("2026-08-17 12:34:56")]
          ]
        )
      end
    end

    context "with plan-level phases" do
      let(:range_begin) { day_start("2026-08-03") }
      let(:range_end) { day_end("2026-11-10") }
      let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
      let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "49.00"}) }

      before do
        intro_phase.discard!
        standard_phase.discard!
        create(
          :rate_phase,
          organization:,
          plan_rate_card:,
          code: "negotiated_intro",
          position: 1,
          billing_interval_cycle_count: 3,
          rate_override:
        )
        create(
          :rate_phase,
          organization:,
          plan_rate_card:,
          code: "standard",
          position: 2,
          billing_interval_cycle_count: nil
        )
      end

      # HOLDS. The old service resolved the plan entry itself from
      # `plan.applied_rate_cards`; the new one takes it as an argument.
      it "uses the plan phases for a materialized subscription rate card" do
        segments = billed_in(schedule, from: range_begin, to: range_end).first(5)

        expect(segments.map(&:cycle_index)).to eq([0, 0, 1, 2, 3])
        # The original asserted the phase codes; the override is what identifies the phase now.
        expect(segments.map(&:rate_override)).to eq([rate_override, rate_override, rate_override, rate_override, nil])
      end
    end

    context "with a phase override interval" do
      let(:range_begin) { day_start("2026-08-16") }
      let(:range_end) { day_end("2026-08-17") }
      let(:rate_override) do
        create(
          :rate_override,
          organization:,
          billing_interval_count: 2,
          billing_interval_unit: "week"
        )
      end

      before do
        intro_phase.update!(billing_interval_cycle_count: nil, rate_override:)
        standard_phase.discard!
      end

      # SHAPE ONLY. `period_to.to_date == 2026-08-16` becomes `ended_at == 2026-08-17 00:00`.
      it "uses the override interval to generate the cycle window" do
        segment = billed_in(schedule, from: range_begin, to: range_end).sole

        expect(segment.started_at).to eq(t("2026-08-06"))
        expect(segment.ended_at).to eq(t("2026-08-17"))
        expect(segment.cycle_index).to eq(0)
        expect(segment.rate_override).to eq(rate_override)
      end
    end

    context "with an override interval followed by a base interval" do
      let(:range_begin) { day_start("2026-08-03") }
      let(:range_end) { day_end("2026-10-31") }
      let(:rate_override) do
        create(
          :rate_override,
          organization:,
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end

      before do
        rate_card.rates.find_each { |rate| rate.update!(billing_interval_unit: "month") }
        intro_phase.update!(billing_interval_cycle_count: 6, rate_override:)
      end

      # DELETED, now UNPORTABLE. The original "uses the original anchor by default" asserted
      # that cycle 6 — the first monthly cycle after a six-cycle weekly override phase — ran
      # `2026-09-14` to `2026-10-02 23:59:59.999999`, a month measured from the card's original
      # anchor rather than from where the cadence changed. That is `realign_billing_anchor:
      # false` and nothing else, and the mode was withdrawn per LAGO-1766, so there is nothing
      # left to re-aim it at. It is the one example of the 19 with no successor in this file.
      #
      # Its sibling below is what the engine does now, and it was the non-default half of the
      # same pair; the `context "when realigning the billing anchor"` that used to wrap it is
      # gone with the distinction it drew.

      # SHAPE ONLY. `2026-10-13 23:59:59.999999` becomes `2026-10-14 00:00`.
      it "continues the base interval from the previous cycle end" do
        segment = billed_in(schedule, from: range_begin, to: range_end).find { it.cycle_index == 6 }

        expect(segment.started_at).to eq(t("2026-09-14"))
        expect(segment.ended_at).to eq(t("2026-10-14"))
      end
    end
  end

  describe "BillingPeriods::Dates::AdvanceService" do
    subject(:schedule) do
      described_class.call!(subscription_rate_card:, anchor_policy: Billing::AnchorPolicy::Realigning).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:rate_card) { create(:rate_card, :advance, organization:) }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date:,
        started_at:
      )
    end
    let(:billing_anchor_date) { Date.parse("2022-02-01") }
    let(:started_at) { t("2022-02-01") }
    let(:range_begin) { day_start("2022-03-01") }
    let(:range_end) { day_end("2022-03-31") }
    let(:rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: t("2022-02-01"),
        billing_interval_count: 1,
        billing_interval_unit: "month"
      )
    end

    before { rate }

    context "when excluding periods outside the range" do
      let(:range_begin) { day_start("2022-03-15") }
      let(:range_end) { day_end("2022-03-15") }

      # SHAPE ONLY. `2022-03-31 23:59:59.999999` becomes `2022-04-01 00:00`.
      it "keeps full periods overlapping the range" do
        segments = billed_in(schedule, from: range_begin, to: range_end)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2022-04-01"))
        expect(segments.map { [it.started_at, it.ended_at, it.rate] })
          .to eq([[t("2022-03-01"), t("2022-04-01"), rate]])
      end

      # INTENTIONAL DIVERGENCE on consumed_ratio (CONTRACT BUGS 2 and 4).
      it "does not clamp the period to the requested range" do
        segment = billed_in(schedule, from: range_begin, to: range_end).sole

        expect(segment.started_at).to eq(t("2022-03-01"))
        expect(segment.ended_at).to eq(t("2022-04-01"))
        expect(segment.proration_ratio).to eq(1)
        # Old: 15.fdiv(31), a Float, because date_diff_with_timezone ceils and adds a second
        # at local midnight. New: 14/31 as a Rational — at 2022-03-15 00:00 exactly fourteen
        # days of March have been consumed. CONTRACT BUG 2 (one day-counting rule) and
        # BUG 4 (Rational, not Float).
        expect(schedule.consumed_ratio(segment:, at: t("2022-03-15"))).to eq(Rational(14, 31))
      end
    end

    # SHAPE ONLY. `exclude_out_of_range: false` for advance is a plain overlap test.
    it "returns the period starting at the billing boundary" do
      segments = schedule.segments_overlapping(range_begin..range_end)

      expect(schedule.next_billing_at(after: range_end)).to eq(t("2022-04-01"))
      expect(segments.map { [it.started_at, it.ended_at, it.rate] })
        .to eq([[t("2022-03-01"), t("2022-04-01"), rate]])
    end

    context "with different rate effective dates" do
      let(:billing_anchor_date) { Date.parse("2026-08-03") }
      let(:started_at) { t("2026-07-01") }
      let(:range_begin) { day_start("2026-08-01") }
      let(:range_end) { day_end("2026-08-14") }
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Date.parse("2026-08-06"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-07-01"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end

      before { second_rate }

      # SHAPE ONLY. Four windows, each inclusive end moved up 1 microsecond.
      it "splits periods at billing boundaries and rate effective dates" do
        segments = schedule.segments_overlapping(range_begin..range_end)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2026-08-17"))
        expect(segments.map { [it.started_at, it.ended_at, it.rate] }).to eq(
          [
            [t("2026-07-27"), t("2026-08-03"), rate],
            [t("2026-08-03"), t("2026-08-06"), rate],
            [t("2026-08-06"), t("2026-08-10"), second_rate],
            [t("2026-08-10"), t("2026-08-17"), second_rate]
          ]
        )
      end
    end

    context "with three rates using different billing intervals" do
      let(:billing_anchor_date) { Date.parse("2026-01-01") }
      let(:started_at) { t("2026-01-01") }
      let(:range_begin) { day_start("2026-01-01") }
      let(:range_end) { day_end("2026-05-31") }
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-01-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-03-15"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:third_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-05-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end

      before do
        second_rate
        third_rate
      end

      # RE-AIMED at Realigning, because the original ran under `realign_billing_anchor: false`
      # and that mode was withdrawn (LAGO-1766).
      #
      # What the example is named for is untouched and is what it still pins: the interval comes
      # from the rate active when the CYCLE OPENS, not from the rate that takes effect inside it
      # — cycle 2 is a whole month, `[Mar 1, Apr 1)`, because the monthly rate is the one active
      # on Mar 1 even though the weekly rate starts on Mar 15 — and a mid-cycle effective date
      # cuts the cycle into segments without moving its boundaries (Mar 15 and May 1 below).
      #
      # What moved is only where each new cadence is measured from. The original pinned 12
      # windows including two one-day cycles, `[Apr 1, Apr 2)` and `[Apr 30, May 1)`: those were
      # the remainders of weekly and monthly fenceposts still ruled from the Jan 1 anchor, and a
      # fixed anchor is the only thing that produces them. Realigning measures the weekly
      # cadence from Apr 1 and the monthly one from May 6, so every cycle is whole, there are 11
      # windows, and `next_billing_at` is Jun 6 rather than Jun 1.
      it "uses the interval active at the cycle start while splitting on effective dates" do
        segments = schedule.segments_overlapping(range_begin..range_end)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2026-06-06"))
        expect(segments.map { [it.started_at, it.ended_at, it.rate] }).to eq(
          [
            [t("2026-01-01"), t("2026-02-01"), rate],
            [t("2026-02-01"), t("2026-03-01"), rate],
            [t("2026-03-01"), t("2026-03-15"), rate],
            [t("2026-03-15"), t("2026-04-01"), second_rate],
            [t("2026-04-01"), t("2026-04-08"), second_rate],
            [t("2026-04-08"), t("2026-04-15"), second_rate],
            [t("2026-04-15"), t("2026-04-22"), second_rate],
            [t("2026-04-22"), t("2026-04-29"), second_rate],
            [t("2026-04-29"), t("2026-05-01"), second_rate],
            [t("2026-05-01"), t("2026-05-06"), third_rate],
            [t("2026-05-06"), t("2026-06-06"), third_rate]
          ]
        )
      end
    end
  end

  describe "BillingPeriods::Dates::ArrearsService" do
    subject(:schedule) do
      described_class.call!(subscription_rate_card:, anchor_policy: Billing::AnchorPolicy::Realigning).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date:,
        started_at:
      )
    end
    let(:billing_anchor_date) { Date.parse("2022-02-01") }
    let(:started_at) { t("2022-02-01") }
    let(:range_begin) { day_start("2022-03-01") }
    let(:range_end) { day_end("2022-03-01") }
    let(:rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: t("2022-02-01"),
        billing_interval_count: 1,
        billing_interval_unit: "month"
      )
    end

    before { rate }

    # SHAPE ONLY. `exclude_out_of_range: false` for arrears was a due-by test, never an
    # overlap (S7): the in-progress March cycle was not in the old result either.
    it "returns the period that closed at the billing boundary" do
      segments = schedule.segments_due_by(range_end)

      expect(schedule.next_billing_at(after: range_end)).to eq(t("2022-04-01"))
      expect(segments.map { [it.started_at, it.ended_at, it.rate] })
        .to eq([[t("2022-02-01"), t("2022-03-01"), rate]])
    end

    context "when excluding periods outside the range" do
      # INTENTIONAL DIVERGENCE — this is the example BLIND_DESIGN 2.2 names by line number
      # ("the spec is green and the revenue is gone") and CHARACTERIZATION S3 measures.
      #
      # Old: `include_period?` dropped the closed February cycle because its inclusive end
      # (2022-02-28 23:59:59.999999) is 1 microsecond before range_begin (2022-03-01 00:00),
      # so ScheduleService returned early, never advanced the clock, and the card stalled
      # forever. New: the engine has no lower bound; segments_due_by — which is what the
      # call site does — hands back the cycle that closed on the boundary.
      it "returns no periods while preserving the next billing boundary" do
        segments = schedule.segments_due_by(range_end)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2022-04-01"))
        expect(windows(segments)).to eq([[t("2022-02-01"), t("2022-03-01")]])
      end
    end

    context "with different rate effective dates" do
      let(:billing_anchor_date) { Date.parse("2026-08-03") }
      let(:started_at) { t("2026-07-01") }
      let(:range_begin) { day_start("2026-08-01") }
      let(:range_end) { day_end("2026-08-14") }
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-07-01"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Date.parse("2026-08-06"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end

      before { second_rate }

      # SHAPE ONLY. The old lower bound here was `at(cycle_index + 2) > range_begin` — "the
      # cycle after this one closes after the range starts", a one-cycle-loose accident
      # (R46) with no successor. The four windows it pinned are the tail of the due list.
      it "splits shifted periods at billing boundaries and rate effective dates" do
        segments = schedule.segments_due_by(range_end).last(4)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2026-08-17"))
        expect(segments.map { [it.started_at, it.ended_at, it.rate] }).to eq(
          [
            [t("2026-07-20"), t("2026-07-27"), rate],
            [t("2026-07-27"), t("2026-08-03"), rate],
            [t("2026-08-03"), t("2026-08-06"), rate],
            [t("2026-08-06"), t("2026-08-10"), second_rate]
          ]
        )
      end

      context "when excluding periods outside the range" do
        let(:range_begin) { day_start("2026-08-03") }
        let(:range_end) { day_end("2026-09-08") }

        # SHAPE ONLY. Six windows, exactly the six the original pinned.
        it "skips fully out-of-range periods while preserving the generated next billing boundary" do
          segments = billed_in(schedule, from: range_begin, to: range_end)

          expect(schedule.next_billing_at(after: range_end)).to eq(t("2026-09-14"))
          expect(segments.map { [it.started_at, it.ended_at, it.rate] }).to eq(
            [
              [t("2026-08-03"), t("2026-08-06"), rate],
              [t("2026-08-06"), t("2026-08-10"), second_rate],
              [t("2026-08-10"), t("2026-08-17"), second_rate],
              [t("2026-08-17"), t("2026-08-24"), second_rate],
              [t("2026-08-24"), t("2026-08-31"), second_rate],
              [t("2026-08-31"), t("2026-09-07"), second_rate]
            ]
          )
        end
      end
    end

    context "with three rates using different billing intervals" do
      let(:billing_anchor_date) { Date.parse("2026-01-01") }
      let(:started_at) { t("2026-01-01") }
      let(:range_begin) { day_start("2026-01-01") }
      let(:range_end) { day_end("2026-06-01") }
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-01-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-03-15"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:third_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: t("2026-05-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end

      before do
        second_rate
        third_rate
      end

      # RE-AIMED at Realigning for the same reason as its advance twin, and to the same walk:
      # the two differ only in which of those windows has fallen due. The original pinned the
      # same twelve fixed-anchor windows and `next_billing_at` Jul 1. Here the walk stops at the
      # monthly cycle `[May 6, Jun 6)`, which has not closed by the range end, so ten windows
      # are due and the next boundary is Jun 6.
      it "uses the interval active at the cycle start while splitting on effective dates" do
        segments = schedule.segments_due_by(range_end)

        expect(schedule.next_billing_at(after: range_end)).to eq(t("2026-06-06"))
        expect(segments.map { [it.started_at, it.ended_at, it.rate] }).to eq(
          [
            [t("2026-01-01"), t("2026-02-01"), rate],
            [t("2026-02-01"), t("2026-03-01"), rate],
            [t("2026-03-01"), t("2026-03-15"), rate],
            [t("2026-03-15"), t("2026-04-01"), second_rate],
            [t("2026-04-01"), t("2026-04-08"), second_rate],
            [t("2026-04-08"), t("2026-04-15"), second_rate],
            [t("2026-04-15"), t("2026-04-22"), second_rate],
            [t("2026-04-22"), t("2026-04-29"), second_rate],
            [t("2026-04-29"), t("2026-05-01"), second_rate],
            [t("2026-05-01"), t("2026-05-06"), third_rate]
          ]
        )
      end
    end
  end
end
