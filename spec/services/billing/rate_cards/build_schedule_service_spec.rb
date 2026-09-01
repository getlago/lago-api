# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::BuildScheduleService do
  subject(:result) { described_class.call(subscription_rate_card:, plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { nil }
  let(:ended_at) { nil }

  let(:subscription_rate_card) do
    create(
      :subscription_rate_card,
      organization:, subscription:, customer:, rate_card:,
      billing_anchor_date: Date.new(2026, 1, 1),
      started_at: Time.utc(2026, 1, 15, 14, 30),
      next_billing_at: Time.utc(2026, 2, 1),
      ended_at:
    )
  end

  before do
    create(
      :rate_card_rate,
      organization:, rate_card:,
      effective_from: Time.utc(2025, 1, 1),
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
  end

  it "carries the card's anchor, timing and end onto the schedule" do
    cycle = result.schedule.cycles_due_by(Time.utc(2026, 3, 1)).first

    expect(result).to be_success
    expect(cycle.started_at...cycle.ended_at).to eq(Time.utc(2026, 1, 15)...Time.utc(2026, 2, 1))
    expect(cycle.due_at).to eq(Time.utc(2026, 2, 1))
  end

  # A card attached at 14:30 is billed for that whole day, and the flooring happens in the
  # customer's timezone rather than UTC.
  context "with a customer timezone" do
    let(:timezone) { "Europe/Paris" }

    it "opens the first cycle at the start of the signing day there" do
      cycle = result.schedule.cycles_due_by(Time.utc(2026, 3, 1)).first

      expect(cycle.started_at).to eq(Time.utc(2026, 1, 14, 23))
    end
  end

  context "when the card has ended" do
    let(:ended_at) { Time.utc(2026, 1, 20) }

    it "stops the schedule there" do
      cycles = result.schedule.cycles_due_by(Time.utc(2026, 6, 1))

      expect(cycles.sole.ended_at).to eq(Time.utc(2026, 1, 20))
    end
  end

  describe "phases" do
    # No phases at all: the card bills on its own cadence forever, which is one open phase.
    it "gives a card without phases a single open phase" do
      cycles = result.schedule.cycles_due_by(Time.utc(2026, 3, 1))

      expect(cycles.map { |cycle| cycle.phase.cycle_count }).to eq([nil, nil])
      expect(cycles.map { |cycle| cycle.phase.code }).to eq([nil, nil])
    end

    context "with a bounded phase carrying an interval override" do
      let(:rate_override) do
        create(:rate_override, organization:, billing_interval_count: 1, billing_interval_unit: "week")
      end

      before do
        create(
          :rate_phase,
          organization:,
          plan_rate_card: nil,
          subscription_rate_card:,
          position: 1,
          code: "weekly_intro",
          billing_interval_cycle_count: 2,
          rate_override:
        )
      end

      # Two weekly cycles, then the card's own monthly cadence takes over: the default phase
      # is appended because every configured phase is bounded.
      it "uses the override cadence and then falls back to the card's" do
        cycles = result.schedule.cycles_due_by(Time.utc(2026, 4, 1))

        expect(cycles.first(2).map { |cycle| [cycle.started_at.to_date.to_s, cycle.phase.code] }).to eq(
          [["2026-01-15", "weekly_intro"], ["2026-01-22", "weekly_intro"]]
        )
        expect(cycles[2].started_at.to_date.to_s).to eq("2026-01-29")
        expect(cycles[2].phase.code).to be_nil
      end

      it "carries the override so the caller can price the cycle with it" do
        expect(result.schedule.cycles_due_by(Time.utc(2026, 2, 1)).first.phase.override).to eq(rate_override)
      end
    end

    # Phases live on the plan entry until the subscription overrides them.
    context "with phases on the plan entry" do
      let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:, units: 1) }

      before do
        create(
          :rate_phase,
          organization:, plan_rate_card:, position: 1, code: "intro",
          billing_interval_cycle_count: 2
        )
      end

      it "reads them through the plan" do
        expect(result.schedule.cycles_due_by(Time.utc(2026, 2, 1)).first.phase.code).to eq("intro")
      end
    end
  end

  # RateCardRate#normalize_effective_from floors an arrears rate to midnight, so only an
  # advance rate can take effect part-way through the day the card is attached. The cadence
  # has to come from the rate that also prices the first window — Billing::Segments picks
  # that one at the window's start, 00:00 — or the card bills weekly windows at the monthly
  # rate's price.
  context "when a rate takes effect later on the day the card is attached" do
    let(:rate_card) { create(:rate_card, :advance, organization:) }

    before do
      create(
        :rate_card_rate,
        organization:, rate_card:,
        effective_from: Time.utc(2026, 1, 15, 8),
        billing_interval_count: 1,
        billing_interval_unit: "week"
      )
    end

    it "takes the cadence from the rate in force when the window opens" do
      cycle = result.schedule.cycles_due_by(Time.utc(2026, 3, 1)).first

      expect(cycle.started_at...cycle.ended_at).to eq(Time.utc(2026, 1, 15)...Time.utc(2026, 2, 1))
    end

    # The later rate is not ignored — it cuts the cycle into two priced windows instead.
    it "bills the change as a segment rather than as a new cadence" do
      cycle = result.schedule.cycles_due_by(Time.utc(2026, 3, 1)).first
      segments = cycle.segments(rates: rate_card.rates.order(:effective_from))

      expect(segments.map { |segment| [segment.started_at, segment.ended_at] }).to eq(
        [[Time.utc(2026, 1, 15), Time.utc(2026, 1, 15, 8)],
          [Time.utc(2026, 1, 15, 8), Time.utc(2026, 2, 1)]]
      )
    end
  end

  # QA plan R2: "No rate = no fee is expected behavior, not an error."
  #
  # A card can start before its first rate without anyone doing anything odd: a rate made
  # effective "Jan 1" is stored at 00:00 UTC, and a customer west of Greenwich signing at
  # that instant is still on Dec 31 where they are. The card is not broken — it just has
  # nothing to bill yet.
  context "when the card starts before its first rate" do
    before do
      rate_card.rates.update_all(effective_from: Time.utc(2026, 3, 1)) # rubocop:disable Rails/SkipsModelValidations
    end

    it "still schedules the card, on the cadence the coming rate asks for" do
      cycles = result.schedule.cycles_due_by(Time.utc(2026, 5, 1))

      expect(result).to be_success
      expect(cycles.map { |cycle| cycle.started_at.to_date.to_s }).to eq(%w[2026-01-15 2026-02-01 2026-03-01 2026-04-01])
    end

    it "bills nothing until the rate lands, then bills normally" do
      rates = rate_card.rates.order(:effective_from)
      billed = result.schedule.cycles_due_by(Time.utc(2026, 5, 1)).map do |cycle|
        [cycle.started_at.to_date.to_s, cycle.segments(rates:).size]
      end

      expect(billed).to eq([["2026-01-15", 0], ["2026-02-01", 0], ["2026-03-01", 1], ["2026-04-01", 1]])
    end
  end

  context "when the card has no rates at all" do
    before { rate_card.rates.destroy_all }

    it "cannot be scheduled" do
      expect(result).not_to be_success
      expect(result.error.error_code).to eq("rate_not_found")
    end
  end
end
