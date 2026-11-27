# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ResolveFixedUnitsService do
  subject(:result) { described_class.call(segments: [segment], cycle:, operation:) }

  let(:operation) { nil }
  let(:units_change) do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
      reason: "contract_units_change", billing_at: change_time, target_cycle_started_at: cycle.started_at,
      units_before: 8, units_after: changed_units)
  end
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 3, 1, 5)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, proration: true) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 8,
      effective_date: Date.new(2026, 3, 1), billing_anchor_date: Date.new(2026, 3, 1))
  end
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 3, 1, 5)) }
  let(:calendar) do
    Billing::Calendar.new(anchor_date: Date.new(2026, 3, 1), timezone: customer.applicable_timezone,
      interval: Billing::Interval.from(rate))
  end
  let(:schedule) { Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule }
  let(:cycle) { schedule.cycle_at(Time.utc(2026, 3, 1, 5)) }
  let(:segment) do
    build(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate: rate,
      started_at: cycle.started_at, ended_at: BillingSegment.inclusive_end(cycle.ended_at), proration_ratio: 1)
  end
  let(:change_time) { Time.utc(2026, 3, 15, 16, 30) }
  let(:changed_units) { 5 }

  before do
    rate
    units_change
  end

  it "uses elapsed seconds across a daylight-saving transition" do
    elapsed = (change_time.to_r - cycle.started_at.to_r).to_d(30)
    duration = (cycle.ended_at.to_r - cycle.started_at.to_r).to_d(30)
    expected_units = (8 * elapsed + 5 * (duration - elapsed)) / duration

    expect(result.segments.sole.units).to eq(expected_units)
    expect(result.segments.sole.units_intervals.map { it[:units] }).to eq(["8.0", "5.0"])
  end

  context "when the change is at the next period boundary" do
    let(:change_time) { Time.utc(2026, 4, 1, 4) }

    it "excludes it from the current period" do
      expect(result.segments.sole.units).to eq(8)
      expect(result.segments.sole.units_intervals.size).to eq(1)
    end
  end

  context "when the card is paid in advance" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, proration: true) }

    it "uses cycle-start units for renewal rather than a later decrease" do
      expect(result.segments.sole.units).to eq(8)
    end
  end

  context "when adjusting existing advance coverage" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, proration: true) }
    let(:changed_units) { 10 }
    let(:operation) { units_change }
    let(:previous_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:previous_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, invoice: previous_invoice,
        action_type: "renew_fixed_advance", billing_at: cycle.started_at, target_cycle_started_at: cycle.started_at,
        processed_at: cycle.started_at)
    end
    let(:saved_units) { 8 }
    let(:save_segment) { true }
    let(:saved_ended_at) { cycle.ended_at }

    before do
      previous_operation
      if previous_operation && save_segment
        previous_operation.segments.create!(organization:, position: 0, rate_card_rate: rate,
          started_at: cycle.started_at, ended_at: saved_ended_at, proration_ratio: 1, units: saved_units)
      end
    end

    it "uses the quantities saved on the completed operation" do
      expect(result.segments.sole).to have_attributes(units: 10, prepaid_units: 8)
    end

    it "does not query invoices or fees to resolve prepaid units" do
      queries = capture_sql { result }

      expect(result).to be_success
      expect(result.segments.sole.prepaid_units).to eq(8)
      expect(queries.grep(/FROM "(?:invoices|fees)"/)).to be_empty
    end

    context "when saved units are zero" do
      let(:saved_units) { 0 }

      it "accepts zero as a saved quantity" do
        expect(result).to be_success
        expect(result.segments.sole.prepaid_units).to eq(0)
      end
    end

    context "when a billed segment has no saved quantity" do
      let(:saved_units) { nil }

      it "returns an error without querying invoices or fees" do
        queries = capture_sql { result }

        expect(result).to be_failure
        expect(result.error.messages).to eq(operation: ["missing_saved_units"])
        expect(queries.grep(/FROM "(?:invoices|fees)"/)).to be_empty
      end
    end

    context "when billed coverage has no saved segments" do
      let(:save_segment) { false }

      it "returns an error" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(operation: ["missing_saved_units"])
      end
    end

    context "when only part of billed coverage has a saved quantity" do
      let(:saved_ended_at) { change_time }

      before do
        previous_operation.segments.create!(organization:, position: 1, rate_card_rate: rate,
          started_at: change_time, ended_at: cycle.ended_at, proration_ratio: 1, units: nil)
      end

      it "returns an error instead of ignoring the incomplete segment" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(operation: ["missing_saved_units"])
      end
    end

    context "when missing quantities belong to other billing work" do
      let(:other_card) { create(:contract_rate_card, organization:, contract:) }

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card: other_card, invoice: previous_invoice,
          action_type: "renew_fixed_advance", target_cycle_started_at: cycle.started_at, processed_at: cycle.started_at)
        create(:billing_operation, organization:, customer:, contract_rate_card:, invoice: previous_invoice,
          action_type: "renew_fixed_advance", target_cycle_started_at: cycle.ended_at, processed_at: cycle.started_at)
        create(:billing_operation, organization:, customer:, contract_rate_card:, invoice: previous_invoice,
          action_type: "renew_fixed_advance", target_cycle_started_at: cycle.started_at)
      end

      it "uses only completed coverage for the same card and cycle" do
        expect(result).to be_success
        expect(result.segments.sole.prepaid_units).to eq(8)
      end
    end

    context "when a billed reconciliation has no saved quantity" do
      let(:previous_adjustment) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, invoice: previous_invoice,
          action_type: "reconcile_advance_coverage", billing_at: change_time - 1.day,
          target_cycle_started_at: cycle.started_at, processed_at: change_time - 1.day,
          units_before: 8, units_after: 9)
      end

      before do
        previous_adjustment.segments.create!(organization:, position: 0, rate_card_rate: rate,
          started_at: change_time - 1.day, ended_at: cycle.ended_at, proration_ratio: 1, units: nil)
      end

      it "returns an error even when the renewal has saved quantities" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(operation: ["missing_saved_units"])
      end
    end

    context "when an operation completed without an invoice or saved quantities" do
      let(:previous_invoice) { nil }
      let(:saved_units) { nil }

      it "does not treat the operation as billed coverage" do
        expect(result).to be_success
        expect(result.segments.sole).to have_attributes(units: 10, prepaid_units: 0)
      end
    end

    context "without an earlier operation" do
      let(:previous_operation) { nil }

      it "has no prepaid units to subtract" do
        expect(result).to be_success
        expect(result.segments.sole.prepaid_units).to eq(0)
      end
    end
  end
end
