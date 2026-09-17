# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::BuildScheduleService do
  subject(:result) { described_class.call(contract_rate_card:, plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.utc(2026, 1, 1), ended_at:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { nil }
  let(:ended_at) { nil }

  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:, contract:, rate_card:,
      billing_anchor_date: Date.new(2026, 1, 1),
      effective_date: Date.new(2026, 1, 15),
      next_billing_at: Time.utc(2026, 2, 1)
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

  it "builds a schedule when rates are available" do
    expect(result).to be_success
    expect(result.schedule).to be_a(Billing::RateCards::Schedule)
  end

  it "carries the card's anchor, timing and end onto the schedule" do
    segment = result.schedule.segments_due_by(Time.utc(2026, 3, 1)).first

    expect(result).to be_success
    expect(segment.started_at...segment.ended_at).to eq(Time.utc(2026, 1, 15)...Time.utc(2026, 2, 1))
    expect(segment.billing_at).to eq(Time.utc(2026, 2, 1))
  end

  # The service is what knows a card has been billed before, so the walk it hands back starts at
  # the last billed cycle rather than replaying the card.
  context "when the card has already been billed for some cycles" do
    # The card's own first three cycles: anchored Jan 1 and attached Jan 15, the first is a stub
    # running to the anchor's next boundary rather than a whole month.
    before do
      [[Time.utc(2026, 1, 15), Time.utc(2026, 2, 1)],
        [Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)],
        [Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)]].each do |opens_at, closes_at|
        create(
          :billing_segment,
          organization:, contract:, customer:, contract_rate_card:,
          rate_card_rate: rate_card.rates.sole,
          cycle_started_at: opens_at, started_at: opens_at, billing_at: closes_at,
          ended_at: BillingSegment.inclusive_end(closes_at)
        )
      end
    end

    it "resumes at the last billed cycle instead of walking from the card's start" do
      cycles = result.schedule.segments_due_by(Time.utc(2026, 6, 1))

      expect(cycles.map(&:cycle_index)).to eq([2, 3, 4])
      expect(cycles.first.started_at).to eq(Time.utc(2026, 3, 1))
    end

    it "answers the same cycles the full walk would have" do
      resumed = result.schedule.segments_due_by(Time.utc(2026, 6, 1))
      contract_rate_card.billing_segments.destroy_all
      full = described_class.call(contract_rate_card:).schedule.segments_due_by(Time.utc(2026, 6, 1))

      expect(full.size).to be > resumed.size
      expect(full.map { [it.cycle_index, it.started_at, it.ended_at] })
        .to end_with(*resumed.map { [it.cycle_index, it.started_at, it.ended_at] })
    end

    it "does not carry billing history into a separate attachment of the same rate card" do
      contract_rate_card.update!(ended_date: Date.new(2026, 6, 30))
      successor = create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 7, 1), billing_anchor_date: Date.new(2026, 1, 1))
      schedule = described_class.call!(contract_rate_card: successor).schedule

      expect(schedule.segments_due_by(Time.utc(2026, 8, 1)).map(&:cycle_index)).to eq([0])
    end
  end

  context "when resuming the first cycle of an attachment" do
    before do
      create(:billing_segment, organization:, contract:, customer:, contract_rate_card:,
        rate_card_rate: rate_card.rates.sole,
        cycle_started_at: Time.utc(2026, 1, 15), started_at: Time.utc(2026, 1, 15),
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)), billing_at: Time.utc(2026, 2, 1))
    end

    it "resumes at midnight of the card's effective date" do
      expect(result).to be_success
      expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).sole.cycle_started_at)
        .to eq(Time.utc(2026, 1, 15))
    end
  end

  context "with persisted advance segments" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", proration: true) }
    let(:billed_segment) do
      create(:billing_segment, organization:, contract:, customer:, contract_rate_card:,
        rate_card_rate: rate_card.rates.sole, status: :done,
        cycle_started_at: Time.utc(2026, 1, 15), started_at: Time.utc(2026, 1, 15),
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)), billing_at: Time.utc(2026, 1, 15))
    end

    it "resumes from the cycle start when the persisted segment is only its last slice" do
      applied = create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
      create(:rate_phase, organization:, plan_rate_card: applied, code: "intro", billing_interval_cycle_count: 1)
      new_rate = create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 20))
      create(:billing_segment, organization:, contract:, customer:, contract_rate_card:,
        rate_card_rate: new_rate, cycle_started_at: Time.utc(2026, 1, 15), started_at: Time.utc(2026, 1, 20),
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)), billing_at: Time.utc(2026, 1, 20))

      segments = result.schedule.segments_due_by(Time.utc(2026, 2, 1))

      expect(segments.map { |segment| [segment.cycle_index, segment.cycle_started_at, segment.rate_phase_code] })
        .to eq([[0, Time.utc(2026, 1, 15), "intro"], [0, Time.utc(2026, 1, 15), "intro"], [1, Time.utc(2026, 2, 1), nil]])
    end

    it "measures consumption against the saved segment after the card terminates" do
      persisted = billed_segment
      contract.update!(ended_at: Time.utc(2026, 1, 20, 12))
      segment = Billing::Segments::Segment.new(
        started_at: persisted.started_at, ended_at: BillingSegment.exclusive_end(persisted.ended_at),
        rate: persisted.rate_card_rate
      )
      schedule = described_class.call!(contract_rate_card:).schedule

      consumed = [Time.utc(2026, 1, 20), Time.utc(2026, 1, 20, 12), Time.utc(2026, 2, 1)]
        .map { |at| schedule.consumed_ratio(segment:, at:) }

      # The original segment covers 17 days, even though the card has now ended inside it.
      expect(consumed).to eq([5.fdiv(17), 6.fdiv(17), 1.0])
      expect(schedule.next_billing_at(after: contract.ended_at)).to be_nil
    end
  end

  # Effective dates are local calendar days, not UTC midnights.
  context "with a customer timezone" do
    let(:timezone) { "Europe/Paris" }

    it "opens the first cycle at the start of the signing day there" do
      cycle = result.schedule.segments_due_by(Time.utc(2026, 3, 1)).first

      expect(cycle.started_at).to eq(Time.utc(2026, 1, 14, 23))
    end
  end

  # The card's effective date and inherited anchor must use the same customer-local day.
  context "when the signing instant falls on a different date where the customer is" do
    let(:timezone) { "America/New_York" }

    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        billing_anchor_date: contract.effective_billing_anchor_date,
        effective_date: contract.started_at.in_time_zone(timezone).to_date,
        next_billing_at: Time.utc(2026, 2, 15)
      )
    end

    let(:contract) do
      create(:contract, organization:, customer:, catalog_plan:, started_at: Time.utc(2026, 1, 15, 2))
    end

    it "derives the anchor in the customer's calendar, not in UTC" do
      expect(contract.effective_billing_anchor_date).to eq(Date.new(2026, 1, 14))
    end

    it "opens a single first cycle, not a one-day stub before the anchor" do
      first = result.schedule.segments_due_by(Time.utc(2026, 4, 1)).first

      expect(first.cycle_index).to eq(0)
      expect(first.started_at).to eq(Time.utc(2026, 1, 14, 5))
      expect(first.ended_at).to eq(Time.utc(2026, 2, 14, 5))
    end
  end

  # The hint is a shortcut, not the only route. The termination and credit paths build a
  # schedule from the card alone, and passing nil straight through made the resolver fall
  # back to `nil&.rate_phases.to_a` — so every phase and every override the plan configured
  # disappeared, with no error and no clue on the invoice.
  describe "resolving the plan entry when the caller has no hint" do
    let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 5) }
    let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "1.00"}) }

    before do
      plan_rate_card
      create(:rate_phase, organization:, plan_rate_card:, code: "intro",
        billing_interval_cycle_count: 1, position: 1, rate_override_id: rate_override.id)
    end

    it "finds the plan entry itself when none is handed in" do
      schedule = described_class.call(contract_rate_card:).schedule
      first = schedule.segments_due_by(Time.utc(2026, 4, 1)).first

      expect(first.rate_phase_code).to eq("intro")
      expect(first.rate_override).to eq(rate_override)
    end

    it "answers the same whether the hint is handed in or looked up" do
      with_hint = described_class.call(contract_rate_card:, plan_rate_card:).schedule
      without = described_class.call(contract_rate_card:).schedule
      codes = ->(s) { s.segments_due_by(Time.utc(2026, 4, 1)).map { |cycle| cycle.rate_phase_code } }

      expect(codes.call(without)).to eq(codes.call(with_hint))
    end

    # A hint for a different card is a caller bug, and silently ignoring it prices the card
    # at the base rate — the same invisible failure, arrived at from the other side.
    it "refuses a hint that prices a different rate card" do
      other = create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:))

      expect { described_class.call(contract_rate_card:, plan_rate_card: other) }
        .to raise_error(described_class::MismatchedPlanRateCard, /prices rate card/)
    end
  end

  # The window is a fact about SERVICE; the price is a decision about BILLING. The schedule
  # closes where service stopped, and the termination day is still paid in full — but by the
  # day-ownership rule, not by stretching the boundary. Stretching it would record a window
  # service never covered, and usage metering reads these boundaries to pick its events.
  context "when the contract has ended" do
    # Prorating, so the day count is visible in the ratio rather than flattened to 1.0. A fixed
    # product, because proration on a usage product needs a recurring metric behind it.
    let(:rate_card) do
      create(:rate_card, organization:, proration: true, product: create(:product, :fixed, organization:))
    end
    let(:ended_at) { Time.utc(2026, 1, 20, 14, 30) }

    def final_slice = result.schedule.segments_due_by(Time.utc(2026, 6, 1)).last

    # The card opened Jan 15 and closed part-way through the 20th: six days begun, out of the
    # 31 in the January interval the slice sits in.
    it "closes where service stopped, and still bills that day whole" do
      expect(final_slice.ended_at).to eq(ended_at)
      expect(final_slice.proration_ratio).to eq(6.fdiv(31))
    end

    # The one instant where the two readings differ. Service ran for none of the 20th, so the
    # 20th is not billed — 19 days, not 20. Rounding the boundary up to the 21st would charge
    # a day the customer never entered.
    context "when it ended on the first instant of a day" do
      let(:ended_at) { Time.utc(2026, 1, 20) }

      it "bills nothing for the day it ended on" do
        expect(final_slice.ended_at).to eq(ended_at)
        expect(final_slice.proration_ratio).to eq(5.fdiv(31))
      end
    end

    # 2026-01-21 02:00 UTC is still the 20th in New York. The boundary is the raw instant
    # either way; what the timezone decides is the day COUNT, and reading it in UTC would
    # bill a day the customer never entered.
    context "when the customer is west of UTC" do
      let(:timezone) { "America/New_York" }
      let(:ended_at) { Time.utc(2026, 1, 21, 2) }

      it "counts the days where the customer is" do
        expect(final_slice.ended_at).to eq(ended_at)
        expect(final_slice.proration_ratio).to eq(6.fdiv(31))
      end
    end
  end

  context "when the card has an inclusive end date" do
    let(:rate_card) { create(:rate_card, organization:, proration: true, product: create(:product, :fixed, organization:)) }

    before { contract_rate_card.update!(ended_date: Date.new(2026, 1, 20)) }

    it "covers the whole final day and stops at the next local midnight" do
      segment = result.schedule.segments_due_by(Time.utc(2026, 2, 1)).sole

      expect(segment.ended_at).to eq(Time.utc(2026, 1, 21))
      expect(segment.proration_ratio).to eq(6.fdiv(31))
      expect(result.schedule.next_billing_at(after: segment.ended_at)).to be_nil
    end

    context "with a customer timezone" do
      let(:timezone) { "America/New_York" }

      it "converts the end date in the customer's timezone" do
        expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).sole.ended_at)
          .to eq(Time.utc(2026, 1, 21, 5))
      end
    end

    context "when the contract ends earlier" do
      let(:ended_at) { Time.utc(2026, 1, 18, 12) }

      it "stops at the contract end" do
        expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).sole.ended_at).to eq(ended_at)
      end
    end

    it "does not extend the card when the caller supplies a later termination" do
      schedule = described_class.call!(contract_rate_card:, ends_at: Time.utc(2026, 1, 25)).schedule

      expect(schedule.segments_due_by(Time.utc(2026, 2, 1)).sole.ended_at).to eq(Time.utc(2026, 1, 21))
    end
  end

  context "without a catalog plan" do
    let(:catalog_plan) { nil }

    it "builds a schedule from the card's rates" do
      expect(result).to be_success
      expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).sole.rate).to eq(rate_card.rates.sole)
    end
  end

  describe "phases" do
    # No phases at all: the card bills on its own cadence forever, which is one open phase.
    it "gives a card without phases a single open phase" do
      cycles = result.schedule.segments_due_by(Time.utc(2026, 3, 1))

      expect(cycles.map(&:rate_override)).to eq([nil, nil])
      expect(cycles.map { |cycle| cycle.rate_phase_code }).to eq([nil, nil])
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
          contract_rate_card:,
          position: 1,
          code: "weekly_intro",
          billing_interval_cycle_count: 2,
          rate_override:
        )
      end

      # Two weekly cycles, then the card's own monthly cadence takes over: the default phase
      # is appended because every configured phase is bounded.
      it "uses the override cadence and then falls back to the card's" do
        cycles = result.schedule.segments_due_by(Time.utc(2026, 4, 1))

        expect(cycles.first(2).map { |cycle| [cycle.started_at.to_date.to_s, cycle.rate_phase_code] }).to eq(
          [["2026-01-15", "weekly_intro"], ["2026-01-22", "weekly_intro"]]
        )
        expect(cycles[2].started_at.to_date.to_s).to eq("2026-01-29")
        expect(cycles[2].rate_phase_code).to be_nil
      end

      it "carries the override so the caller can price the cycle with it" do
        expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).first.rate_override).to eq(rate_override)
      end
    end

    # Phases live on the plan entry until the contract overrides them.
    context "with phases on the plan entry" do
      let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 1) }

      before do
        create(
          :rate_phase,
          organization:, plan_rate_card:, position: 1, code: "intro",
          billing_interval_cycle_count: 2
        )
      end

      it "reads them through the plan" do
        expect(result.schedule.segments_due_by(Time.utc(2026, 2, 1)).first.rate_phase_code).to eq("intro")
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
      segments = result.schedule.segments_due_by(Time.utc(2026, 3, 1))
        .select { |segment| segment.cycle_started_at == Time.utc(2026, 1, 15) }

      expect(segments.first.started_at...segments.last.ended_at)
        .to eq(Time.utc(2026, 1, 15)...Time.utc(2026, 2, 1))
    end

    # The later rate is not ignored — it cuts the cycle into two priced windows instead.
    it "bills the change as a segment rather than as a new cadence" do
      segments = result.schedule.segments_due_by(Time.utc(2026, 3, 1))
        .select { it.cycle_started_at == Time.utc(2026, 1, 15) }

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
      segments = result.schedule.segments_due_by(Time.utc(2026, 5, 1))

      expect(result).to be_success
      expect(segments.map(&:cycle_index)).to eq([2, 3])
      expect(segments.map { |segment| segment.started_at.to_date.to_s }).to eq(%w[2026-03-01 2026-04-01])
    end

    it "bills nothing until the rate lands, then bills normally" do
      expect(result.schedule.segments_due_by(Time.utc(2026, 3, 1))).to be_empty
      segments = result.schedule.segments_due_by(Time.utc(2026, 5, 1))

      expect(segments.map { |segment| [segment.cycle_index, segment.started_at.to_date.to_s] })
        .to eq([[2, "2026-03-01"], [3, "2026-04-01"]])
    end
  end

  # The walk is lazy, so a phase carrying a bad cadence used to build a schedule that looked
  # fine and raised on the first question asked of it — past this service's own `success?`,
  # from inside a method that only asks about dates. Contract materialization is the live caller
  # and it guards with `success?`, so the raise escaped it.
  context "when a rate phase overrides the cadence with an impossible one" do
    before do
      # billing_interval_count is nullable with no CHECK behind it, so a legacy row or an
      # update_all reaches the engine with a count no cadence can be built from.
      override = create(:rate_override, organization:, billing_interval_unit: "week")
      override.update_columns(billing_interval_count: 0) # rubocop:disable Rails/SkipsModelValidations
      create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card:,
        position: 1, code: "broken", billing_interval_cycle_count: 2, rate_override: override)
    end

    it "fails the result rather than raising when the schedule is walked" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("invalid_billing_schedule")
      expect(result.error.error_message).to eq("interval count must be a positive integer, got 0")
      expect(result.schedule).to be_nil
    end

    context "when the invalid override belongs to a later phase" do
      before do
        contract_rate_card.rate_phases.sole.update!(position: 2)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card:,
          position: 1, code: "valid_intro", billing_interval_cycle_count: 2)
      end

      it "fails the build before the walker reaches that phase" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("invalid_billing_schedule")
        expect(result.error.error_message).to eq("interval count must be a positive integer, got 0")
      end
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
