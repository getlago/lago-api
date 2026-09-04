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
#   3. when the cadence changes, billing re-anchors on the day it changes — every
#      production caller of the previous engine passed realign_billing_anchor: true,
#      and LAGO-1766 settled it as the only behaviour ("reading B, everything is glued")
#
# The previous engine stored `period_to` inclusively; this one is half-open, so every
# expectation below is the old one with the end moved to the next instant.
RSpec.describe Billing::RateCards::BuildScheduleService do
  describe "cadence from the rates in force" do
    subject(:schedule) do
      described_class.call(subscription_rate_card:).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:rate_card) { create(:rate_card, :advance, organization:) }

    let(:rates) { rate_card.rates.order(:effective_from) }

    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:, subscription:, customer:, rate_card:,
        billing_anchor_date: Date.new(2026, 1, 1),
        started_at: Time.utc(2026, 1, 1),
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

    # What the engine actually bills: every cycle reaching into the window, cut into the
    # segments each one is priced as. This is the previous engine's `periods`.
    def t(*parts) = Time.utc(*parts).to_fs(:db)

    def billed_windows(from, to)
      schedule.cycles_overlapping(from...to).flat_map do |cycle|
        cycle.segments(rates:).map { |segment| [segment.started_at.to_fs(:db), segment.ended_at.to_fs(:db), segment.rate.code] }
      end
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

    it "reports the next billing instant on the cadence in force" do
      expect(schedule.due_after(Time.utc(2026, 5, 20))).to eq(Time.utc(2026, 6, 6))
    end

    # Reading A, which LAGO-1766 weighed and declined: the cadence still follows the rates,
    # but the billing day never moves off the card's own anchor. Nothing passes this today —
    # it is here so the reading the ticket rejected stays exercised and reversible.
    context "when the billing anchor is not realigned" do
      subject(:schedule) do
        described_class.call(subscription_rate_card:, realign_billing_anchor: false).schedule
      end

      it "keeps counting from the card's own anchor when the cadence changes" do
        expect(billed_windows(Time.utc(2026, 4, 1), Time.utc(2026, 5, 1))).to eq(
          [
            # Weekly, but on the Thursdays counted from Jan 1 rather than from Apr 1, which
            # leaves the 1st alone as the tail of the week that began in March.
            [t(2026, 4, 1), t(2026, 4, 2), "weekly"],
            [t(2026, 4, 2), t(2026, 4, 9), "weekly"],
            [t(2026, 4, 9), t(2026, 4, 16), "weekly"],
            [t(2026, 4, 16), t(2026, 4, 23), "weekly"],
            [t(2026, 4, 23), t(2026, 4, 30), "weekly"],
            # The last week runs past the window asked for; cycles are returned whole, and the
            # monthly rate splits this one on May 1 without ending it there.
            [t(2026, 4, 30), t(2026, 5, 1), "weekly"],
            [t(2026, 5, 1), t(2026, 5, 7), "monthly_again"]
          ]
        )
      end
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
    subject(:schedule) { described_class.call(subscription_rate_card:).schedule }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:rates) { rate_card.rates.order(:effective_from) }

    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:, subscription:, customer:, rate_card:,
        billing_anchor_date: Date.new(2026, 8, 3),
        started_at: Time.utc(2026, 7, 1),
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
      windows = schedule.cycles_due_by(Time.utc(2026, 8, 20)).map { |cycle| [cycle.started_at.to_fs(:db), cycle.ended_at.to_fs(:db)] }

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
      segments = schedule.cycles_overlapping(Time.utc(2026, 8, 3)...Time.utc(2026, 8, 17))
        .flat_map { |cycle| cycle.segments(rates:) }
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
      described_class.call(subscription_rate_card:, ends_at: terminated_at).schedule
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:rates) { rate_card.rates.order(:effective_from) }
    let(:terminated_at) { Time.utc(2026, 8, 17, 12, 34, 56) }

    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:, subscription:, customer:, rate_card:,
        billing_anchor_date: Date.new(2026, 8, 3),
        started_at: Time.utc(2026, 8, 3),
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
      segments = schedule.cycles_due_by(Time.utc(2026, 9, 1))
        .flat_map { |cycle| cycle.segments(rates:) }
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
      expect(schedule.due_after(Time.utc(2027, 1, 1))).to be_nil
    end
  end
end
