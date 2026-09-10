# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService do
  subject(:result) { described_class.call(invoice:, metered_item:, billing_context:, options:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:billing_context) { Billing::Context.from(contract:) }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "USD", status: :generating) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "USD") }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "9"}, min_amount_cents:)
  end
  let(:min_amount_cents) { 0 }
  let(:billing_segment) do
    create(
      :billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
      currency: "USD", rate_properties: {"amount" => "2"},
      cycle_started_at: Time.utc(2026, 8, 1), started_at: Time.utc(2026, 8, 1),
      ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1)), billing_at: Time.utc(2026, 9, 1)
    )
  end
  let(:product_filter) { nil }
  let(:metered_item) { described_class::MeteredItem.from_billing_segment(billing_segment) }
  let(:options) { described_class::Options.new(context: :finalize) }

  before do
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: billable_metric.code, timestamp: Time.utc(2026, 8, 10), properties: {region: "eu"})
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: billable_metric.code, timestamp: Time.utc(2026, 8, 20), properties: {region: "us"})
  end

  it "persists a product fee using the segment price without charge properties" do
    expect(result).to be_success
    expect(result.fees.sole.reload).to have_attributes(
      invoice:, invoiceable: product, fee_type: "product", charge_id: nil, subscription_id: nil,
      product_filter_id: nil, charge_filter_id: nil, rate_card_rate:, rate_override_id: nil,
      amount_cents: 400, units: 2, events_count: 2
    )
    expect(result.fees.sole.properties).to eq({})
  end

  it "does not instantiate or call a charge cache" do
    allow(Subscriptions::ChargeCacheMiddleware).to receive(:new).and_call_original
    supplied_cache = instance_double(Subscriptions::ChargeCacheMiddleware)

    response = described_class.call(invoice:, metered_item:, billing_context:, options:, cache_middleware: supplied_cache)

    expect(response).to be_success
    expect(response.fees.sole.amount_cents).to eq(400)
    expect(Subscriptions::ChargeCacheMiddleware).not_to have_received(:new)
  end

  it "prices distinct windows independently on the same invoice" do
    billing_segment.update!(ended_at: BillingSegment.inclusive_end(Time.utc(2026, 8, 15)))
    first_fee = result.fees.sole
    later_segment = create(
      :billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
      currency: "USD", rate_properties: {"amount" => "3"}, cycle_started_at: billing_segment.cycle_started_at,
      started_at: Time.utc(2026, 8, 15), ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1))
    )
    later_item = described_class::MeteredItem.from_billing_segment(later_segment)

    later_result = described_class.call!(invoice:, metered_item: later_item, billing_context:, options:)

    expect([first_fee.amount_cents, later_result.fees.sole.amount_cents]).to eq([200, 300])
    expect(invoice.fees.count).to eq(2)
  end

  context "with current usage" do
    let(:options) { described_class::Options.new(context: :current_usage) }

    it "computes in memory without persisting fees" do
      expect { result }.not_to change(Fee, :count)
      expect(result.fees.sole).to be_new_record
      expect(result.fees.sole).to have_attributes(fee_type: "product", amount_cents: 400)
    end
  end

  context "when aggregation fails" do
    before do
      aggregator = instance_double(BillableMetrics::Aggregations::CountService)
      aggregation_result = BillableMetrics::Aggregations::BaseService::Result.new
      aggregation_result.service_failure!(code: "aggregation_failed", message: "Aggregation failed")
      allow(aggregator).to receive(:aggregate).and_return(aggregation_result)
      allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_return(aggregator)
    end

    it "returns the failure without persisting fees or attempting true-up" do
      allow(Fees::CreateTrueUpService).to receive(:call).and_call_original

      expect { result }.not_to change(Fee, :count)
      expect(result).not_to be_success
      expect(result.error.code).to eq("aggregation_failed")
      expect(Fees::CreateTrueUpService).not_to have_received(:call)
    end
  end

  context "without an invoice" do
    let(:invoice) { nil }

    it "persists product fees without a subscription" do
      expect(result.fees.sole.invoice_id).to be_nil
      expect(result.fees.sole.subscription_id).to be_nil
    end
  end

  context "with a legacy charge linked to the product" do
    let(:charge) { create(:standard_charge, billable_metric:) }
    let(:product) { create(:product, organization:, billable_metric:, charge:) }

    before { create(:charge_filter, charge:, properties: {amount: "100"}) }

    it "does not expand legacy filters or persist legacy fee identity" do
      expect(result.fees.sole.reload).to have_attributes(
        invoiceable: product, fee_type: "product", charge_id: nil, charge_filter_id: nil, amount_cents: 400
      )
    end
  end

  context "with product filters" do
    let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us apac]) }
    let(:eu_filter) { create(:product_filter, organization:, product:) }
    let(:us_filter) { create(:product_filter, organization:, product:) }

    before do
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
      create(:product_filter_value, organization:, product_filter: us_filter, billable_metric_filter: region, value: "us")
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.utc(2026, 8, 21), properties: {region: "apac"})
    end

    it "only prices unmatched events for an unscoped rate card" do
      expect(result).to be_success
      expect(result.fees.sole).to have_attributes(product_filter_id: nil, units: 1, amount_cents: 200)
      expect(invoice.fees.pluck(:product_filter_id, :charge_filter_id)).to eq([[nil, nil]])
    end

    context "with a selected filter" do
      let(:product_filter) { eu_filter }

      it "only prices the rate card's selected bucket" do
        expect(result.fees.sole.reload).to have_attributes(product_filter_id: eu_filter.id, charge_filter_id: nil, units: 1, amount_cents: 200)
      end

      context "with a minimum amount" do
        let(:min_amount_cents) { 1000 }

        it "attaches the true-up to the scoped fee and clears its filter identity" do
          fees = result.fees

          expect(fees.map(&:amount_cents)).to eq([200, 800])
          expect(fees.first.product_filter_id).to eq(eu_filter.id)
          expect(fees.last).to have_attributes(
            invoiceable: product, fee_type: "product", product_filter_id: nil,
            charge_filter_id: nil, true_up_parent_fee: fees.first
          )
        end
      end
    end

    context "with a minimum amount" do
      let(:min_amount_cents) { 1000 }

      it "computes the unscoped card's true-up using only default usage" do
        fees = result.fees
        default_fee = fees.find { |fee| fee.product_filter_id.nil? && fee.true_up_parent_fee_id.nil? }

        expect(fees.map(&:amount_cents)).to eq([200, 800])
        expect(fees.last).to have_attributes(
          invoiceable: product, fee_type: "product", product_filter_id: nil,
          charge_filter_id: nil, true_up_parent_fee: default_fee
        )
        expect(invoice.fees.count).to eq(2)
      end
    end

    context "when the scoped bucket fails aggregation" do
      let(:product_filter) { us_filter }

      before do
        failed_aggregation = BillableMetrics::Aggregations::BaseService::Result.new
        failed_aggregation.service_failure!(code: "aggregation_failed", message: "Aggregation failed")
        failed_aggregator = instance_double(BillableMetrics::Aggregations::CountService, aggregate: failed_aggregation)
        allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_wrap_original do |original, **arguments|
          if arguments[:metered_item].filter_id == us_filter.id
            failed_aggregator
          else
            original.call(**arguments)
          end
        end
      end

      it "does not persist a partial set of product fees" do
        expect { result }.not_to change(Fee, :count)
        expect(result).not_to be_success
        expect(result.error.code).to eq("aggregation_failed")
      end
    end
  end

  context "with a draft invoice" do
    let(:invoice) { create(:invoice, organization:, customer:, currency: "USD", status: :draft) }

    it "skips adjusted-fee lookup even without the skip option" do
      allow(AdjustedFee).to receive(:where).and_call_original

      expect(result.fees.sole.amount_cents).to eq(400)
      expect(AdjustedFee).not_to have_received(:where)
    end
  end

  context "with recurring aggregation updates" do
    before do
      billable_metric.update!(aggregation_type: :sum_agg, field_name: "value", recurring: true)
      aggregator = instance_double(BillableMetrics::Aggregations::SumService)
      aggregation_result = BillableMetrics::Aggregations::BaseService::Result.new
      aggregation_result.aggregation = 2
      aggregation_result.count = 2
      aggregation_result.recurring_updated_at = Time.utc(2026, 8, 20)
      allow(aggregator).to receive(:aggregate).and_return(aggregation_result)
      allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_return(aggregator)
    end

    it "does not persist charge-shaped cached aggregations" do
      expect { result }.not_to change(CachedAggregation, :count)
      expect(result).to be_success
      expect(result.fees.sole.amount_cents).to eq(400)
      expect(result.cached_aggregations).to be_nil
    end
  end

  context "with a minimum amount" do
    let(:min_amount_cents) { 1000 }

    it "uses the segment proration ratio" do
      billing_segment.update!(proration_ratio: 0.5)

      expect(result.fees.map(&:amount_cents)).to eq([400, 100])
      expect(result.fees.last).to have_attributes(fee_type: "product", rate_card_rate:, true_up_parent_fee: result.fees.first)
    end

    it "does not create a true-up at or above the minimum" do
      billing_segment.update!(rate_properties: {"amount" => "5"})

      expect(result.fees.sole.amount_cents).to eq(1000)
    end

    it "bills the minimum even when no events match" do
      billing_segment.update!(started_at: Time.utc(2026, 8, 25))

      expect(result.fees.map(&:amount_cents)).to eq([0, 1000])
    end

    it "uses the override minimum and preserves pricing identity" do
      override = create(:rate_override, organization:, min_amount_cents: 1400)
      billing_segment.update!(rate_override: override, proration_ratio: 0.5)

      expect(result.fees.map(&:amount_cents)).to eq([400, 300])
      expect(result.fees.map(&:rate_override)).to eq([override, override])
    end

    context "with pricing units" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", applied_pricing_unit_code: pricing_unit.code) }
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, min_amount_cents:, applied_pricing_unit_conversion_rate: 0.5)
      end

      before { billing_segment.update!(pricing_unit:, proration_ratio: 0.5) }

      it "converts the prorated minimum and usage with the segment conversion rate" do
        expect(result.fees.map(&:amount_cents)).to eq([200, 300])
        expect(result.fees.map { |fee| fee.pricing_unit_usage.amount_cents }).to eq([400, 600])
        expect(result.fees.last.pricing_unit_usage).to have_attributes(pricing_unit:, conversion_rate: 0.5)
      end

      it "uses the override conversion rate rather than the catalog rate" do
        override = create(:rate_override, organization:, min_amount_cents: 1000, pricing_unit_conversion_rate: 0.25)
        billing_segment.update!(rate_override: override)

        expect(result.fees.map(&:amount_cents)).to eq([100, 400])
        expect(result.fees.map { |fee| fee.pricing_unit_usage.conversion_rate }).to eq([0.25, 0.25])
      end
    end
  end
end
