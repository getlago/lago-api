# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ResolveFixedUnitsService do
  subject(:result) { described_class.call(segments: [segment], cycle:, operation:) }

  let(:operation) { nil }
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
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: changed_units, effective_date: nil, effective_at: change_time)
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
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "adjust_fixed_advance",
        reason: "contract_units_change", billing_at: change_time, target_cycle_started_at: cycle.started_at)
    end
    let(:previous_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:pricing_segments) { nil }
    let(:previous_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, invoice: previous_invoice,
        action_type: "renew_fixed_advance", billing_at: cycle.started_at, target_cycle_started_at: cycle.started_at,
        processed_at: cycle.started_at, pricing_segments:)
    end
    let(:fee_properties) do
      {"from_datetime" => cycle.started_at.iso8601(6), "to_datetime" => BillingSegment.inclusive_end(cycle.ended_at).iso8601(6)}
    end
    let(:other_card) { create(:contract_rate_card, organization:, contract:) }
    let(:other_rate) { create(:rate_card_rate, organization:, rate_card: other_card.rate_card) }

    before do
      previous_operation
      if previous_invoice
        create(:fee, organization:, invoice: previous_invoice, subscription: nil, contract:, contract_rate_card:,
          rate_card_rate: rate, invoiceable: product, fee_type: :product, pay_in_advance: true, units: 8, properties: fee_properties)
        create(:fee, organization:, invoice: previous_invoice, subscription: nil, contract:, contract_rate_card: other_card,
          rate_card_rate: other_rate, invoiceable: other_card.product, fee_type: :product, pay_in_advance: true, units: 20, properties: fee_properties)
      end
    end

    it "reads legacy fee coverage and excludes fees for another card" do
      expect(result.segments.sole).to have_attributes(units: 10, prepaid_units: 8)
    end

    context "with saved pricing inputs" do
      let(:pricing_segments) do
        [{"started_at" => cycle.started_at.iso8601(6), "ended_at" => cycle.ended_at.iso8601(6), "units" => "9.0"}]
      end

      it "uses the saved coverage instead of reconstructing it from fees" do
        expect(result.segments.sole).to have_attributes(units: 10, prepaid_units: 9)
      end
    end

    context "without an earlier invoice" do
      let(:previous_invoice) { nil }

      it "has no prepaid units to subtract" do
        expect(result.segments.sole).to have_attributes(units: 10, prepaid_units: 0)
      end
    end
  end
end
