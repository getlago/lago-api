# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::BuildService do
  subject(:result) { described_class.call(contract_rate_card:, **obligation.pricing_inputs_for(segment), pricing_units_by_code:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:billable_metric) { create(:billable_metric, organization:, recurring: true, aggregation_type: "sum_agg", field_name: "amount") }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", billing_timing:, proration:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "12"}) }
  let(:billing_timing) { :arrears }
  let(:proration) { true }
  let(:terms) { Billing::Terms.new(timing: billing_timing, prorated: proration) }
  let(:pricing_units_by_code) { nil }
  let(:cycle_started_at) { Time.zone.parse("2026-02-01") }
  let(:exclusive_end) { Time.zone.parse("2026-03-01") }
  let(:started_at) { cycle_started_at }
  let(:cycle_end) { Time.zone.parse("2026-03-01") }
  let(:interval_unit) { :month }
  let(:timezone) { "UTC" }
  let(:anchor_date) { cycle_started_at.to_date }
  let(:rate_override) { nil }
  let(:phase) { Billing::Phase.new(code: nil, billing_interval_cycle_count: nil, rate_override:) }
  let(:calendar) do
    Billing::Calendar.new(anchor_date:,
      interval: Billing::Interval.new(count: 1, unit: interval_unit), timezone:)
  end
  let(:cycle) { Billing::Cycle.new(index: 0, started_at: cycle_started_at, ended_at: cycle_end, phase:, calendar:) }
  let(:segment) { Billing::Segments::Segment.new(started_at:, ended_at: exclusive_end, rate:) }
  let(:obligation_billing_at) { cycle_end }
  let(:obligation) { Billing::Obligation.new(cycle:, segments: [segment], billing_at: obligation_billing_at, terms:) }

  it "builds an in-memory slice with the priced associations and inclusive period end" do
    built_segment = result.billing_segment

    expect(built_segment).to have_attributes(
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      billable_metric_code: contract_rate_card.rate_card.product.billable_metric.code,
      rate_card_rate: rate,
      rate_properties: {"amount" => "12"},
      currency: "USD",
      cycle_started_at:,
      started_at: cycle_started_at,
      ended_at: exclusive_end - BillingSegment::MICROSECOND,
      billing_at: exclusive_end,
      proration_ratio: 1
    )
    expect(built_segment).not_to respond_to(:save, :reload, :persisted?)
  end

  context "when the obligation terms differ from the rate card" do
    let(:started_at) { Time.utc(2026, 2, 10) }
    let(:terms) { Billing::Terms.new(timing: :advance, prorated: false) }

    it "uses the obligation's pricing anchor and proration without changing coverage" do
      expect(result.billing_segment).to have_attributes(
        started_at: Time.utc(2026, 2, 10),
        ended_at: Time.utc(2026, 3, 1) - BillingSegment::MICROSECOND,
        billing_at: Time.utc(2026, 2, 10),
        proration_ratio: 1.0
      )
    end
  end

  shared_examples "preserves the terms-based fee boundaries" do
    it "uses the terms anchor and the complete slice coverage" do
      billing_segment = result.billing_segment
      item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:)

      expect(billing_segment.billing_at).to eq(expected_billing_at)
      expect(item.boundaries).to have_attributes(
        from_datetime: started_at,
        to_datetime: exclusive_end - BillingSegment::MICROSECOND,
        charges_from_datetime: started_at,
        charges_to_datetime: exclusive_end - BillingSegment::MICROSECOND,
        timestamp: expected_billing_at
      )
      expect(item.filtered_for_charge_boundaries).to eq(
        "from_datetime" => started_at.utc.iso8601(6),
        "to_datetime" => (exclusive_end - BillingSegment::MICROSECOND).utc.iso8601(6),
        "charges_from_datetime" => started_at.utc.iso8601(6),
        "charges_to_datetime" => (exclusive_end - BillingSegment::MICROSECOND).utc.iso8601(6),
        "charges_duration" => 19, # February 10 through February 28, inclusive.
        "timestamp" => expected_billing_at,
        "fixed_charges_from_datetime" => nil,
        "fixed_charges_to_datetime" => nil,
        "fixed_charges_duration" => nil,
        "product_filter_values" => nil
      )
    end
  end

  context "with a mid-cycle slice" do
    let(:started_at) { Time.zone.parse("2026-02-10") }
    let(:proration) { false }
    let(:expected_billing_at) { exclusive_end }

    include_examples "preserves the terms-based fee boundaries"

    context "when billing normally in advance" do
      let(:billing_timing) { :advance }
      let(:obligation_billing_at) { started_at }
      let(:expected_billing_at) { started_at }

      include_examples "preserves the terms-based fee boundaries"
    end

    context "when regrouping paid advance fees at the end of the slice" do
      let(:billing_timing) { :advance }
      let(:expected_billing_at) { started_at }
      let(:rate_card) do
        create(:rate_card, organization:, product:, currency: "USD", billing_timing:,
          proration:, regroup_paid_fees: :invoice, display_on_invoice: false)
      end

      include_examples "preserves the terms-based fee boundaries"
    end
  end

  context "with a partial prorated slice" do
    let(:started_at) { Time.utc(2026, 2, 10) }

    it "prices 19 of February's 28 days" do
      expect(result.billing_segment.proration_ratio).to eq((19.to_d / 28).round(10))
    end
  end

  context "with a phase override" do
    let(:rate_override) { instance_double(RateOverride, properties: {"amount" => "7"}) }

    it "uses the complete override properties while retaining the base rate" do
      expect(result.billing_segment).to have_attributes(rate_card_rate: rate, rate_override:, rate_properties: {"amount" => "7"})
    end

    context "without a base rate" do
      let(:rate) { nil }

      it "prices from the override" do
        expect(result.billing_segment.rate_properties).to eq({"amount" => "7"})
      end
    end
  end

  context "without a rate or override" do
    let(:rate) { nil }

    it "rejects the unpriced slice" do
      expect { result }.to raise_error(ArgumentError, "a billable segment needs a rate or an override to price it")
    end
  end

  context "with an applied pricing unit" do
    let(:unit) { create(:pricing_unit, organization:, code: "credits") }

    before do
      rate
      allow(rate_card).to receive(:applied_pricing_unit_code).and_return("credits")
    end

    it "finds the unit in the card's organization" do
      unit
      expect(result.billing_segment.pricing_unit).to eq(unit)
    end

    context "with a batched lookup" do
      let(:pricing_units_by_code) { {"credits" => unit} }

      it "uses the supplied unit" do
        expect(result.billing_segment.pricing_unit).to eq(unit)
      end

      context "when the unit is missing from the batch" do
        let(:pricing_units_by_code) { {} }

        it "does not fall back to a database lookup" do
          unit
          expect { result }.to raise_error(BaseService::FailedResult)
        end
      end
    end

    context "when only another organization has the unit" do
      let(:unit) { create(:pricing_unit, code: "credits") }

      it "does not find the other organization's unit" do
        unit
        expect { result }.to raise_error(BaseService::FailedResult)
      end
    end
  end

  context "with a fixed product" do
    let(:product) { create(:product, :fixed, organization:) }

    it "captures no billable metric code" do
      expect(result.billing_segment.billable_metric_code).to be_nil
    end
  end
end
