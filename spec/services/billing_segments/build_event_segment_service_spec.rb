# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::BuildEventSegmentService do
  subject(:result) { described_class.call(contract_rate_card:, billable_segment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "12"}) }
  let(:cycle_started_at) { Time.zone.parse("2026-02-01") }
  let(:exclusive_end) { Time.zone.parse("2026-03-01") }
  let(:billable_segment) do
    Billing::BillableSegment.new(cycle_index: 0, cycle_started_at:, started_at: cycle_started_at,
      ended_at: exclusive_end, billing_at: exclusive_end, rate:, rate_override: nil,
      proration_ratio: 1, rate_phase_code: nil)
  end

  it "builds an in-memory slice with the priced associations and inclusive period end" do
    segment = result.billing_segment

    expect(segment).to have_attributes(
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
    expect(segment).not_to respond_to(:save, :reload, :persisted?)
  end

  shared_examples "preserves the terms-based fee boundaries" do
    it "uses the terms anchor and the complete slice coverage" do
      segment = result.billing_segment
      item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment)

      expect(segment.billing_at).to eq(expected_billing_at)
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
    let(:billing_timing) { :arrears }
    let(:canonical_billing_at) { exclusive_end }
    let(:expected_billing_at) { exclusive_end }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", billing_timing:) }
    let(:billable_segment) do
      Billing::BillableSegment.new(cycle_index: 0, cycle_started_at:, started_at:,
        ended_at: exclusive_end, billing_at: canonical_billing_at, rate:, rate_override: nil,
        proration_ratio: 1, rate_phase_code: nil)
    end

    include_examples "preserves the terms-based fee boundaries"

    context "when billing normally in advance" do
      let(:billing_timing) { :advance }
      let(:canonical_billing_at) { started_at }
      let(:expected_billing_at) { started_at }

      include_examples "preserves the terms-based fee boundaries"
    end

    context "when regrouping paid advance fees at the end of the slice" do
      let(:billing_timing) { :advance }
      let(:expected_billing_at) { started_at }
      let(:rate_card) do
        create(:rate_card, organization:, product:, currency: "USD", billing_timing:,
          regroup_paid_fees: :invoice, display_on_invoice: false)
      end

      include_examples "preserves the terms-based fee boundaries"
    end
  end

  context "with a fixed product" do
    let(:product) { create(:product, :fixed, organization:) }

    it "captures no billable metric code" do
      expect(result.billing_segment.billable_metric_code).to be_nil
    end
  end
end
