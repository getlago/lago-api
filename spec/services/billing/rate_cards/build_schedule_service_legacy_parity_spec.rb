# frozen_string_literal: true

require "rails_helper"

# Runs the previous engine and this one over the same inputs and compares what each says
# should be billed. The previous engine's date layer is self-contained — it reaches for no
# model constants — so it is vendored verbatim under spec/legacy_engine and loaded
# here rather than reimplemented.
#
# This exists because the rewrite dropped behaviour silently: the cadence stopped following
# the rates and nobody noticed through a hundred reviews. A spec written from the new code
# can only confirm what the new code does. This one cannot: it asks the old code.
#
# The two disagree on shape, not on meaning, so both sides are normalised before comparing:
#
#   old  period_to is inclusive, a microsecond before the window closes
#   new  segment.ended_at is exclusive, the instant the window stops covering
#
# What is compared is everything a billing_segments row carries from this layer: the window,
# the rate pricing it, the instant the clock owes it, the cycle it belongs to (cycle_started_at)
# and the override in force — every field of the /cycles payload this layer decides. That
# endpoint is what product signed off against on the previous engine, and it asked for
# exclude_out_of_range: false and realign_billing_anchor: true, which is what is used here.
#
# `billing_at` is per segment, not per cycle: a cut cycle bills the piece before the change
# on its own boundary. That is what the oldest engine did; the branch after it moved to the
# cycle's instant, and this engine goes back to the first reading. Persistence itself cannot
# be compared — the previous engine
# wrote to a billing_cycles table that does not exist here — so the values it would have
# written are compared instead, taken straight off its own Period objects.
#
# Known and accepted differences, asserted nowhere below:
#
#   proration_ratio      deliberately different. The old engine counted days with the v1
#                        helper, whose segments do not sum to one across a cut cycle — the
#                        103% bug this PR set out to fix. The invariant is asserted below
#                        against this engine instead of against the old numbers.
#   consumed_ratio       the old Period carried it; this engine has no equivalent yet
#   exclude_out_of_range the old service could filter; this one returns whole cycles and
#                        leaves the choice to the caller
%w[
  models/billing_period_boundaries
  billing_periods/boundaries
  billing_periods/dates_service
  dates/base_service
  dates/advance_service
  dates/arrears_service
  dates/termination_service
  billing_periods/first_period_service
].each { |path| require Rails.root.join("spec/legacy_engine", "#{path}.rb").to_s }

RSpec.describe Billing::RateCards::BuildScheduleService do
  # The old engine took phases through a wrapper this PR deleted, so it is restored here
  # verbatim — walking the phases and returning the one the cycle index falls in. Copied
  # rather than reimplemented, because a paraphrase is exactly how behaviour goes missing.
  def legacy_phases(phases)
    Class.new do
      def initialize(phases) = @phases = phases

      def rate_phase_for_cycle(cycle_index)
        cursor = 0
        @phases.each do |phase|
          count = phase.billing_interval_cycle_count
          return phase if count.nil?

          cursor += count
          return phase if cycle_index < cursor
        end
        nil
      end
    end.new(phases)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:timezone) { scenario_timezone }
  let(:scenario_timezone) { "UTC" }

  # Every combination worth disagreeing about: both timings, a cadence that changes by rate,
  # one that changes by phase override, month-end anchors, and an anchor before the start.
  def self.scenarios
    [
      {name: "monthly throughout",
       anchor: "2026-01-01", starts: "2026-01-01",
       rates: [["a", "2026-01-01", 1, "month"]]},
      {name: "monthly to weekly by rate",
       anchor: "2026-01-01", starts: "2026-01-01",
       rates: [["a", "2026-01-01", 1, "month"], ["b", "2026-03-15", 1, "week"]]},
      {name: "weekly to monthly and back",
       anchor: "2026-01-01", starts: "2026-01-01",
       rates: [["a", "2026-01-01", 1, "week"], ["b", "2026-02-10", 1, "month"], ["c", "2026-05-01", 1, "week"]]},
      {name: "quarterly from a month end",
       anchor: "2026-01-31", starts: "2026-01-31",
       rates: [["a", "2026-01-01", 3, "month"]]},
      {name: "month end clamping",
       anchor: "2026-01-31", starts: "2026-01-31",
       rates: [["a", "2026-01-01", 1, "month"]]},
      {name: "anchor before the start",
       anchor: "2026-08-03", starts: "2026-07-01",
       rates: [["a", "2026-07-01", 1, "week"], ["b", "2026-08-06", 1, "week"]]},
      {name: "start part way through a day",
       anchor: "2026-01-01", starts: "2026-01-15",
       rates: [["a", "2026-01-01", 1, "month"], ["b", "2026-02-20", 2, "week"]]},
      # The windows agree; the next billing instant does not, and this engine is the one
      # that is right. The cycle after Feb 10 is yearly, because that is the rate in force
      # when it opens, so it falls due in 2027. The old engine answered Feb 20 — the next
      # boundary on the cadence that had just ended — because it read the instant off the
      # cycle it had already built instead of resolving the next one.
      #
      # Worth knowing rather than celebrating: a year is a long time for the clock to sleep,
      # and next_billing_at is only recomputed when it wakes. A rate added in between does
      # not pull the wake-up forward on its own.
      {name: "daily then yearly",
       anchor: "2026-01-01", starts: "2026-01-01",
       next_billing_at: "2027-02-10T00:00:00.000000Z",
       rates: [["a", "2026-01-01", 10, "day"], ["b", "2026-02-01", 1, "year"]]},
      # A phase pinning the cadence, then the card's own — the shape LAGO-1766 was about.
      {name: "weekly intro phase then the rate",
       anchor: "2026-08-10", starts: "2026-08-10",
       rates: [["a", "2026-01-01", 1, "month"]],
       phases: [[6, 1, "week"], [nil, nil, nil]]},
      # A cut cycle, which is where the two engines part company on the ratio.
      {name: "a cut cycle",
       anchor: "2026-01-01", starts: "2026-01-10",
       rates: [["a", "2026-01-01", 1, "month"], ["b", "2026-02-14", 1, "month"]]},
      # The same cut cycle on a card that does not prorate: every piece is charged whole,
      # which is what both previous engines did and where they agree with this one exactly.
      {name: "a cut cycle on a card that does not prorate",
       anchor: "2026-01-01", starts: "2026-01-10", proration: false,
       rates: [["a", "2026-01-01", 1, "month"], ["b", "2026-02-14", 1, "month"]]},
      # A phase override and a rate change in the same timeline.
      {name: "intro phase over changing rates",
       anchor: "2026-01-01", starts: "2026-01-05",
       rates: [["a", "2026-01-01", 1, "month"], ["b", "2026-03-10", 1, "week"]],
       phases: [[3, 2, "week"], [nil, nil, nil]]}
    ]
  end

  # Timezones are deliberately absent above. The old engine does not keep its periods
  # contiguous outside UTC — it closes a cycle at the customer's local midnight and opens
  # the next at UTC midnight, leaving a hole the width of the offset. Measured: 5 holes over
  # six monthly cycles in Asia/Tokyo, 25 over six months of weekly cycles in Europe/Paris.
  # Matching that would mean reproducing a bug, so these scenarios assert this engine's own
  # invariant instead of agreement.
  def self.timezone_scenarios
    [
      {name: "month end clamping in Tokyo", timezone: "Asia/Tokyo",
       anchor: "2026-01-31", starts: "2026-01-31",
       rates: [["a", "2026-01-01", 1, "month"]]},
      {name: "weekly across a DST change in Paris", timezone: "Europe/Paris",
       anchor: "2026-03-01", starts: "2026-03-01",
       rates: [["a", "2026-01-01", 1, "week"], ["b", "2026-04-20", 1, "month"]]},
      # A card whose local day precedes its first rate, which is what a rate stored at
      # 00:00 UTC does to a customer west of Greenwich. The old engine produced a
      # three-hour period charged as a whole month; this one schedules the card and bills
      # from the rate on (QA plan R2).
      {name: "starting before the first rate in Sao Paulo", timezone: "America/Sao_Paulo",
       anchor: "2026-01-01", starts: "2026-01-01",
       rates: [["a", "2026-01-01", 1, "month"]]}
    ]
  end

  def build_card(scenario, timing)
    rate_card = create(
      :rate_card, organization:, billing_timing: timing,
      # A fixed product so proration is a free choice: RateCard#validate_proration only
      # constrains usage products, where the metric must be recurring.
      product: create(:product, :fixed, organization:),
      proration: scenario.fetch(:proration, true)
    )
    scenario[:rates].each do |code, effective_from, count, unit|
      create(
        :rate_card_rate, organization:, rate_card:, code:,
        effective_from: Time.zone.parse(effective_from),
        billing_interval_count: count, billing_interval_unit: unit
      )
    end
    card = create(
      :subscription_rate_card,
      organization:, subscription:, customer:, rate_card:,
      billing_anchor_date: Date.parse(scenario[:anchor]),
      started_at: Time.zone.parse(scenario[:starts]),
      next_billing_at: Time.zone.parse(scenario[:starts])
    )

    (scenario[:phases] || []).each_with_index do |(cycle_count, count, unit), index|
      override = count && create(:rate_override, organization:,
        billing_interval_count: count, billing_interval_unit: unit)
      create(:rate_phase, :subscription_level, organization:, subscription_rate_card: card,
        position: index + 1, code: "phase_#{index}",
        billing_interval_cycle_count: cycle_count, rate_override: override)
    end

    card
  end

  # The old engine reads six things off the card; five still exist. `proration?` was
  # delegated to the rate card back then and is not on the model now, so it is lent back
  # here rather than reopening the model, which would leak into every other spec.
  def legacy_card(card)
    SimpleDelegator.new(card).tap do |delegated|
      delegated.define_singleton_method(:proration?) { card.rate_card.proration? }
    end
  end

  # The previous engine, asked for everything it would generate up to the range end.
  def legacy_windows(card, range)
    result = BillingPeriods::DatesService.from_subscription_rate_card(
      legacy_card(card),
      rates: card.rate_card.rates.order(:effective_from),
      rate_phases: legacy_phases(card.rate_phases.order(:position).to_a),
      range:,
      options: BillingPeriods::DatesService::Options.new(
        timezone:, exclude_out_of_range: false, realign_billing_anchor: true, termination: false
      )
    )
    windows = result.periods.map do |period|
      # inclusive end -> exclusive, so the two shapes can be compared directly
      [
        period.period_from.utc.iso8601(6),
        (period.period_to + Rational(1, 1_000_000)).utc.iso8601(6),
        period.rate.code,
        # billing_at, before the `max(Time.current)` clamp applied on write. Inclusive on
        # this side, so the arrears end needs the same nudge as the window's.
        (period.rate.rate_card.advance? ? period.period_from : period.period_to + Rational(1, 1_000_000))
          .utc.iso8601(6),
        # The cycle the row belongs to — what billing_segments.cycle_started_at stores, and the
        # index and phase code the /cycles payload shows beside it.
        period.cycle.period_from.utc.iso8601(6),
        period.cycle_index,
        period.rate_phase&.code,
        period.rate_override&.id
      ]
    end

    [windows, result.next_billing_at&.utc&.iso8601(6)]
  end

  def current_windows(card, range)
    schedule = Billing::RateCards::BuildScheduleService.call(subscription_rate_card: card).schedule
    rates = card.rate_card.rates.order(:effective_from)
    from = range.first.in_time_zone(timezone).beginning_of_day
    to = range.last.in_time_zone(timezone).end_of_day

    windows = schedule.cycles_overlapping(from...to).flat_map do |cycle|
      cycle.segments(rates:).map do |segment|
        [
          segment.started_at.utc.iso8601(6),
          segment.ended_at.utc.iso8601(6),
          segment.rate.code,
          cycle.billing_at(segment).utc.iso8601(6),
          cycle.started_at.utc.iso8601(6),
          cycle.index,
          cycle.phase.code,
          cycle.phase.override&.id
        ]
      end
    end

    [windows, schedule.next_due_at(to)&.utc&.iso8601(6)]
  end

  scenarios.each do |scenario|
    %w[arrears advance].each do |timing|
      context "when billing #{scenario[:name]} in #{timing}" do
        let(:scenario_timezone) { scenario[:timezone] || "UTC" }

        it "produces the same windows and the same next billing instant" do
          card = build_card(scenario, timing)
          range = Date.parse(scenario[:starts])..(Date.parse(scenario[:starts]) + 8.months)

          mine_windows, mine_next = current_windows(card, range)
          their_windows, their_next = legacy_windows(card, range)

          expect(mine_windows).to eq(their_windows)
          expect(mine_next).to eq(scenario.fetch(:next_billing_at, their_next))
          # Guards the comparison itself: two empty lists are equal, and pass silently.
          expect(mine_windows.size).to be > 1
        end

        # What the old day count got wrong: however a cycle is cut, its pieces have to add
        # back up to the cycle itself — one for a whole cycle, and its own share when the
        # card's start or end clamps it. The old engine counted days with the v1 helper and
        # summed to more than that, which is the 103% bug this PR fixed.
        # Each segment falls due on its own boundary, not on the cycle's: a rate changing
        # mid-cycle bills the piece before it right away rather than at the cycle's close.
        it "bills each segment on its own boundary" do
          card = build_card(scenario, timing)
          schedule = described_class.call(subscription_rate_card: card).schedule
          rates = card.rate_card.rates.order(:effective_from)
          advance = card.rate_card.advance?

          wrong = schedule.cycles_due_by(Time.zone.parse(scenario[:starts]) + 8.months).flat_map do |cycle|
            cycle.segments(rates:).reject do |segment|
              cycle.billing_at(segment) == (advance ? segment.started_at : segment.ended_at)
            end
          end

          expect(wrong).to be_empty
        end

        it "prorates each cycle into segments that sum back to the cycle" do
          card = build_card(scenario, timing)
          schedule = described_class.call(subscription_rate_card: card).schedule
          rates = card.rate_card.rates.order(:effective_from)
          prorating = scenario.fetch(:proration, true)

          drifted = schedule.cycles_due_by(Time.zone.parse(scenario[:starts]) + 8.months).filter_map do |cycle|
            pieces = cycle.segments(rates:).map { |segment| cycle.proration_ratio(segment) }
            # A card that prorates cuts the cycle into shares that add back up to it; one
            # that does not charges every piece whole, which is what the previous engines
            # stored whenever rate_cards.proration was off.
            expected = prorating ? cycle.proration_ratio(cycle) : pieces.size.to_f
            next if (pieces.sum - expected).abs < 1e-9

            "cycle #{cycle.index} #{cycle.started_at.to_date}: pieces=#{pieces.sum} expected=#{expected}"
          end

          expect(drifted).to be_empty
        end
      end
    end
  end

  timezone_scenarios.each do |scenario|
    context "when billing #{scenario[:name]}" do
      let(:scenario_timezone) { scenario[:timezone] }

      # The property the old engine broke outside UTC: a billing timeline may not have
      # holes. It closed a cycle at the customer's local midnight and opened the next at
      # UTC midnight, leaving the offset unbilled — 5 holes over six monthly cycles in
      # Asia/Tokyo, 25 over six months of weekly cycles in Europe/Paris.
      it "leaves no gap between consecutive cycles" do
        card = build_card(scenario, "arrears")
        cycles = described_class.call(subscription_rate_card: card)
          .schedule.cycles_due_by(Time.zone.parse(scenario[:starts]) + 6.months)

        gaps = cycles.each_cons(2).reject { |before, after| before.ended_at == after.started_at }

        expect(gaps).to be_empty
        expect(cycles.size).to be > 1
      end

      # Every boundary is the customer's own midnight, never the application's.
      it "puts every boundary on a local midnight" do
        card = build_card(scenario, "arrears")
        zone = ActiveSupport::TimeZone[scenario[:timezone]]
        cycles = described_class.call(subscription_rate_card: card)
          .schedule.cycles_due_by(Time.zone.parse(scenario[:starts]) + 6.months)

        offenders = cycles.map(&:started_at).reject { |at| at.in_time_zone(zone) == at.in_time_zone(zone).beginning_of_day }

        expect(offenders).to be_empty
      end
    end
  end
end
