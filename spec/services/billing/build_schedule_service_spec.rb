# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::BuildScheduleService do
  subject(:result) { described_class.call(subscription_rate_card:, plan_rate_card:, ends_at: requested_ends_at) }

  around do |example|
    travel_to(current_time) { example.run }
  end

  let(:current_time) { Time.zone.parse("2024-01-01 00:00:00") }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration:) }
  let(:billing_timing) { "arrears" }
  let(:proration) { false }
  let(:plan_rate_card) { nil }
  let(:requested_ends_at) { nil }
  let(:ended_at) { nil }
  let(:started_at) { Time.zone.parse("2024-01-01 12:00:00") }

  let(:subscription_rate_card) do
    create(
      :subscription_rate_card,
      organization:,
      subscription:,
      customer:,
      rate_card:,
      billing_anchor_date: Date.parse("2024-01-01"),
      started_at:,
      next_billing_at: Time.zone.parse("2024-02-01"),
      ended_at:
    )
  end

  let!(:monthly_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from: Time.zone.parse("2024-01-01 00:00:00"),
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
  end

  def due_by(value)
    result.schedule.segments_due_by(Time.zone.parse(value))
  end

  it "returns a schedule" do
    expect(result.schedule).to be_a(Billing::Schedule)
  end

  it "walks the card's cycles" do
    expect(due_by("2024-03-01").map(&:started_at))
      .to eq([Time.zone.parse("2024-01-01"), Time.zone.parse("2024-02-01")])
  end

  it "takes the cadence from the rate" do
    expect(due_by("2024-03-01").map(&:ended_at))
      .to eq([Time.zone.parse("2024-02-01"), Time.zone.parse("2024-03-01")])
  end

  it "bills an arrears card when its cycle closes" do
    expect(due_by("2024-03-01").map(&:billing_at))
      .to eq([Time.zone.parse("2024-02-01"), Time.zone.parse("2024-03-01")])
  end

  context "when the card bills in advance" do
    let(:billing_timing) { "advance" }

    it "bills when the cycle opens" do
      expect(due_by("2024-02-01").map(&:billing_at))
        .to eq([Time.zone.parse("2024-01-01"), Time.zone.parse("2024-02-01")])
    end
  end

  context "when the card prorates" do
    let(:proration) { true }
    let(:started_at) { Time.zone.parse("2024-01-20 12:00:00") }

    it "prorates the part cycle the card starts in" do
      expect(due_by("2024-02-01").map(&:proration_ratio)).to eq([Rational(12, 31)])
    end
  end

  context "when the card does not prorate" do
    let(:started_at) { Time.zone.parse("2024-01-20 12:00:00") }

    it "prices the part cycle in full" do
      expect(due_by("2024-02-01").map(&:proration_ratio)).to eq([1])
    end
  end

  context "with a customer in another timezone" do
    let(:timezone) { "America/New_York" }

    it "opens cycles at the customer's local midnight" do
      expect(due_by("2024-02-02").map(&:started_at)).to eq([Time.utc(2024, 1, 1, 5)])
    end
  end

  describe "loading rates" do
    # Written first, effective last: a timeline that came out in insertion order would
    # price January with the March rate.
    let(:monthly_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2024-03-01 00:00:00"),
        billing_interval_count: 1,
        billing_interval_unit: "month"
      )
    end

    let!(:earlier_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2024-01-01 00:00:00"),
        billing_interval_count: 1,
        billing_interval_unit: "month"
      )
    end

    before { allow(Billing::RateTimeline).to receive(:new).and_call_original }

    # The three call sites each carried their own LEAD(effective_from) window query to
    # slice the rates around a range. A card holds a handful of rates and the walk needs
    # every one of them to know where the cadence changes, so they are all loaded, oldest
    # first, whatever order they were written in.
    it "loads every rate of the card, oldest first" do
      result

      expect(Billing::RateTimeline).to have_received(:new).with([earlier_rate, monthly_rate])
    end

    it "prices each cycle with the rate in force" do
      expect(due_by("2024-04-01").map(&:rate)).to eq([earlier_rate, earlier_rate, monthly_rate])
    end
  end

  describe "the card start" do
    # A units change opens a new row rather than editing the old one. Reading the new
    # row's own start would clip every cycle to the moment the quantity last moved.
    let(:started_at) { Time.zone.parse("2024-02-15 00:00:00") }

    before do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2024-01-01"),
        started_at: Time.zone.parse("2024-01-01 12:00:00"),
        ended_at: Time.zone.parse("2024-02-15 00:00:00"),
        next_billing_at: Time.zone.parse("2024-02-01")
      )
    end

    it "walks from when the card was first attached, not from the current version" do
      expect(due_by("2024-03-01").map(&:started_at))
        .to eq([Time.zone.parse("2024-01-01"), Time.zone.parse("2024-02-01")])
    end
  end

  describe "the card end" do
    context "when the card has ended" do
      let(:ended_at) { Time.zone.parse("2024-02-10 00:00:00") }

      it "stops the walk there" do
        expect(due_by("2024-06-01").map(&:ended_at))
          .to eq([Time.zone.parse("2024-02-01"), Time.zone.parse("2024-02-10")])
      end
    end

    context "when an end is requested" do
      let(:requested_ends_at) { Time.zone.parse("2024-02-20 00:00:00") }

      it "stops the walk there" do
        expect(due_by("2024-06-01").map(&:ended_at))
          .to eq([Time.zone.parse("2024-02-01"), Time.zone.parse("2024-02-20")])
      end
    end

    context "when an end is requested on a card that already ended" do
      let(:ended_at) { Time.zone.parse("2024-02-10 00:00:00") }
      let(:requested_ends_at) { Time.zone.parse("2024-01-20 00:00:00") }

      it "prefers the requested end" do
        expect(due_by("2024-06-01").map(&:ended_at)).to eq([Time.zone.parse("2024-01-20")])
      end
    end

    context "when the card is open-ended" do
      it "keeps walking" do
        expect(due_by("2025-01-01").map(&:cycle_index)).to eq((0..11).to_a)
      end
    end
  end

  describe "phases" do
    let(:rate_override) { create(:rate_override, organization:, billing_interval_unit: "week") }

    context "with phases on the subscription card" do
      before do
        create(
          :rate_phase,
          organization:,
          plan_rate_card: nil,
          subscription_rate_card:,
          position: 1,
          billing_interval_cycle_count: 2,
          rate_override:
        )
      end

      it "bills the phase on the override's cadence" do
        expect(due_by("2024-02-15").map(&:started_at)).to eq([
          Time.zone.parse("2024-01-01"), Time.zone.parse("2024-01-08"), Time.zone.parse("2024-01-15")
        ])
      end

      it "carries the override on the segments it prices" do
        expect(due_by("2024-02-15").map(&:rate_override)).to eq([rate_override, rate_override, nil])
      end
    end

    context "with phases on the plan card" do
      let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }

      before do
        create(
          :rate_phase,
          organization:,
          plan_rate_card:,
          position: 1,
          billing_interval_cycle_count: 2,
          rate_override:
        )
      end

      it "resolves them through the plan card" do
        expect(due_by("2024-02-15").map(&:rate_override)).to eq([rate_override, rate_override, nil])
      end

      # The plan entry is a hint, not the source of truth. Resolving against an empty list
      # when the caller says nothing would price every cycle at the base rate and drop the
      # phase silently, which is a wrong price with no symptom.
      context "when the caller does not hand over the plan card" do
        subject(:result) { described_class.call(subscription_rate_card:) }

        before { plan_rate_card }

        it "finds it on the subscription's plan" do
          expect(due_by("2024-02-15").map(&:rate_override)).to eq([rate_override, rate_override, nil])
        end
      end

      context "when the caller hands over a plan card for another rate card" do
        subject(:result) { described_class.call(subscription_rate_card:, plan_rate_card: other_plan_rate_card) }

        let(:other_rate_card) { create(:rate_card, organization:, product:) }
        let(:other_plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card: other_rate_card) }

        it "refuses to price this card's phases with another card's" do
          expect { result }.to raise_error(ArgumentError, /prices rate card/)
        end
      end
    end

    context "with no phase at all" do
      it "runs the card on its own cadence" do
        expect(due_by("2024-03-01").map(&:rate_override)).to eq([nil, nil])
      end
    end
  end

  # Both anchor modes are product requirements. A cadence change is what makes the choice
  # observable: the phase's two weekly cycles close on Jan 15, and only a realigning anchor
  # moves the monthly calendar there.
  describe "the anchor policy" do
    let(:rate_override) { create(:rate_override, organization:, billing_interval_unit: "week") }

    before do
      create(
        :rate_phase,
        organization:,
        plan_rate_card: nil,
        subscription_rate_card:,
        position: 1,
        billing_interval_cycle_count: 2,
        rate_override:
      )
    end

    # Realigning is what every call site does today, so it is what a caller that says
    # nothing gets. This service is the one place that will read the setting when the
    # product decides where it lives.
    it "realigns the anchor by default" do
      expect(due_by("2024-02-15").map(&:ended_at)).to eq([
        Time.zone.parse("2024-01-08"), Time.zone.parse("2024-01-15"), Time.zone.parse("2024-02-15")
      ])
    end

    # A second anchor policy lived here and was removed on 2026-09-06: LAGO-1766 ruled
    # against shipping one ("we won't add a `billing_anchor_mode` as a v1"). The
    # `anchor_policy:` parameter is still accepted, so the mode returns without the walk
    # changing — see Billing::AnchorPolicy.
  end

  describe "a card with no rate" do
    let(:monthly_rate) { nil }

    it "fails" do
      expect(result).not_to be_success
    end

    it "names the missing resource" do
      expect(result.error.resource).to eq("rate")
    end

    it "builds no schedule" do
      expect(result.schedule).to be_nil
    end
  end
end
