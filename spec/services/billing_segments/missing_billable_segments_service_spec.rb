# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::MissingBillableSegmentsService do
  subject(:result) { described_class.call(contract_rate_card:, schedule:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: nil) }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01 00:00:00")) }
  let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }

  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 1, 1),
      billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.zone.parse("2026-03-01 00:00:00")
    )
  end

  # A monthly cycle cut in two by a rate change effective mid-February.
  let(:schedule) { Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule }
  let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }

  before do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from: Time.zone.parse("2026-02-15 00:00:00"),
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
  end

  describe "#call" do
    context "when nothing is stored yet" do
      it "returns every segment the schedule reports as due" do
        expect(result.billable_segments.map { [it.started_at, it.billing_at] }).to eq(
          [
            [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")],
            [Time.zone.parse("2026-02-01 00:00:00"), Time.zone.parse("2026-02-15 00:00:00")],
            [Time.zone.parse("2026-02-15 00:00:00"), Time.zone.parse("2026-03-01 00:00:00")]
          ]
        )
      end
    end

    # A rate added inside an already-billed cycle re-splits it, and the later piece starts
    # at the rate's date, not the cycle's. An equal-start test would call it new; writing it
    # would charge a settled period twice and trip the exclusion constraint, failing every
    # later run for this customer.
    context "when a stored segment covers the candidate but starts earlier" do
      before do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          rate_card_rate: rate_card.rates.first,
          cycle_started_at: Time.zone.parse("2026-02-01 00:00:00"),
          started_at: Time.zone.parse("2026-02-01 00:00:00"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-03-01 00:00:00")),
          billing_at: Time.zone.parse("2026-02-01 00:00:00")
        )
      end

      it "treats the whole cycle as settled" do
        expect(result.billable_segments).to eq([])
      end
    end

    # Consecutive pieces share their boundary, so a stored period that begins where a
    # candidate ends touches it without covering any of it. The candidate's end is exclusive
    # for exactly this reason; making it inclusive would settle a period nobody billed.
    context "when a stored segment begins where a candidate ends" do
      before do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          rate_card_rate: rate_card.rates.first,
          cycle_started_at: Time.zone.parse("2026-02-01 00:00:00"),
          started_at: Time.zone.parse("2026-02-15 00:00:00"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-03-01 00:00:00")),
          billing_at: Time.zone.parse("2026-03-01 00:00:00")
        )
      end

      it "still owes the piece that ends there" do
        expect(result.billable_segments.map(&:started_at)).to eq([Time.zone.parse("2026-02-01 00:00:00")])
      end
    end

    context "when the clock has come due but nothing falls due yet" do
      let(:timestamp) { Time.zone.parse("2026-01-15 00:00:00") }

      it "returns nothing, in arrears the January cycle only bills on February 1" do
        expect(result.billable_segments).to eq([])
      end

      it "does not read the card's stored segments, which have no window to be bounded by" do
        schedule # built here, so the builder's own read is not what the spy sees
        allow(contract_rate_card).to receive(:billing_segments).and_call_original

        result

        expect(contract_rate_card).not_to have_received(:billing_segments)
      end
    end

    # The run that billed February 15 stored the cycle's first slice. Resuming from that
    # cycle's start replays the cycle whole, so the schedule hands the stored slice back.
    context "when the cycle is partly stored" do
      before do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          rate_card_rate: rate_card.rates.first,
          cycle_started_at: Time.zone.parse("2026-02-01 00:00:00"),
          started_at: Time.zone.parse("2026-02-01 00:00:00"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-02-15 00:00:00")),
          billing_at: Time.zone.parse("2026-02-15 00:00:00")
        )
      end

      it "hands back only the segment that is not durable yet" do
        expect(result.billable_segments.map(&:started_at)).to eq([Time.zone.parse("2026-02-15 00:00:00")])
      end
    end
  end
end
