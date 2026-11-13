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
  let(:proration_ratio) { BigDecimal("1.0") }
  let(:pricing_unit) { nil }
  let(:billing_segment) do
    build(
      :billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
      currency: "USD", rate_properties:, pricing_unit:, proration_ratio:,
      cycle_started_at: Time.utc(2026, 8, 1), started_at: Time.utc(2026, 8, 1),
      ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1)), billing_at: Time.utc(2026, 9, 1)
    )
  end
  let(:product_filter) { nil }
  let(:rate_properties) { {"amount" => "2"} }
  let(:metered_item) { described_class::MeteredItem.from_billing_segment(billing_segment:) }
  let(:options) { described_class::Options.new(context: :finalize) }

  before do
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: billable_metric.code, timestamp: Time.utc(2026, 8, 10), properties: {region: "eu"})
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: billable_metric.code, timestamp: Time.utc(2026, 8, 20), properties: {region: "us"})
  end

  it "persists a product fee using the segment price and boundary identity" do
    expect(result).to be_success
    expect(result.fees.sole.reload).to have_attributes(
      invoice:, invoiceable: product, fee_type: "product", charge_id: nil, subscription_id: nil,
      contract:, contract_rate_card:,
      product_filter_id: nil, charge_filter_id: nil, rate_card_rate:, rate_override_id: nil,
      amount_cents: 400, units: 2, events_count: 2, pay_in_advance: false
    )
    expect(result.fees.sole.properties).to eq(metered_item.filtered_for_charge_boundaries.as_json)
  end

  context "with an advance rate card shown on the invoice" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, product_filter:, currency: "USD") }

    it "stores the advance billing timing on the fee" do
      expect(result.fees.sole.pay_in_advance).to be(true)
    end
  end

  context "when the interval was already billed" do
    let(:billed_fees) { described_class.call!(invoice:, metered_item:, billing_context:, options:).fees }

    before do
      billed_fees
      allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_call_original
    end

    it "returns the persisted fee set without recalculating or duplicating it" do
      expect { result }.not_to change(Fee, :count)
      expect(result).to be_success
      expect(result.fees).to match_array(billed_fees)
      expect(BillableMetrics::AggregationFactory).not_to have_received(:new_instance)
    end

    context "with grouped fees and a true-up" do
      let(:min_amount_cents) { 1000 }
      let(:rate_properties) { {"amount" => "2", "pricing_group_keys" => ["region"]} }

      it "returns all groups and the true-up with their original identities" do
        expect { result }.not_to change(Fee, :count)
        expect(result.fees).to match_array(billed_fees)
        expect(result.fees.size).to eq(3)
        expect(result.fees.map(&:contract_rate_card)).to eq([contract_rate_card] * 3)
        expect(BillableMetrics::AggregationFactory).not_to have_received(:new_instance)
      end
    end
  end

  context "with an existing fee" do
    let(:fee_invoice) { invoice }
    let(:fee_card) { contract_rate_card }
    let(:fee_from) { billing_segment.started_at.iso8601(6) }
    let(:fee_to) { billing_segment.ended_at.iso8601(6) }
    let(:fee_type) { :product }
    let(:deleted_at) { nil }
    let(:event_id) { nil }
    let(:transaction_id) { nil }
    let!(:existing_fee) do
      create(:fee, organization:, invoice: fee_invoice, contract: fee_card.contract, contract_rate_card: fee_card,
        invoiceable: product, rate_card_rate:, fee_type:, deleted_at:, pay_in_advance_event_id: event_id,
        pay_in_advance_event_transaction_id: transaction_id,
        properties: {charges_from_datetime: fee_from, charges_to_datetime: fee_to})
    end

    shared_examples "a new interval fee" do
      it "calculates a new fee instead of reusing the existing one" do
        expect { result }.to change(Fee, :count).by(1)
        expect(result).to be_success
        expect(result.fees.sole).to have_attributes(amount_cents: 400, contract_rate_card:)
        expect(result.fees.sole.id).not_to eq(existing_fee.id)
      end
    end

    context "without an invoice" do
      let(:invoice) { nil }

      before { allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_call_original }

      it "returns the existing standalone fee without recalculating" do
        expect { result }.not_to change(Fee, :count)
        expect(result.fees).to eq([existing_fee])
        expect(BillableMetrics::AggregationFactory).not_to have_received(:new_instance)
      end

      context "with an invoice-backed fee" do
        let(:fee_invoice) { create(:invoice, organization:, customer:, currency: "USD") }

        include_examples "a new interval fee"
      end

      context "with an advance event fee" do
        let(:event_id) { SecureRandom.uuid }

        include_examples "a new interval fee"
      end

      context "with a legacy charge linked to the product" do
        let(:charge) { create(:standard_charge, billable_metric:) }
        let(:product) { create(:product, organization:, billable_metric:, charge:) }

        it "looks up the segment by contract rate card rather than charge" do
          expect(metered_item.charge).to eq(charge)
          expect(result.fees).to eq([existing_fee])
          expect(BillableMetrics::AggregationFactory).not_to have_received(:new_instance)
        end
      end

      context "with an invoice preview" do
        let(:options) { described_class::Options.new(context: :invoice_preview) }

        it "recalculates without reusing or persisting the standalone fee" do
          expect { result }.not_to change(Fee, :count)
          expect(result.fees.sole).to be_new_record
          expect(result.fees.sole.amount_cents).to eq(400)
        end
      end
    end

    context "with a different invoice" do
      let(:fee_invoice) { create(:invoice, organization:, customer:, currency: "USD") }

      include_examples "a new interval fee"
    end

    context "with a different applied card sharing the catalog rate" do
      let(:other_contract) { create(:contract, organization:, customer:) }
      let(:fee_card) { create(:contract_rate_card, organization:, contract: other_contract, rate_card:) }

      include_examples "a new interval fee"
    end

    context "with a start boundary differing by one microsecond" do
      let(:fee_from) { (billing_segment.started_at + Rational(1, 1_000_000)).iso8601(6) }

      include_examples "a new interval fee"
    end

    context "with an end boundary differing by one microsecond" do
      let(:fee_to) { (billing_segment.ended_at - Rational(1, 1_000_000)).iso8601(6) }

      include_examples "a new interval fee"
    end

    context "with a discarded fee" do
      let(:deleted_at) { Time.current }

      include_examples "a new interval fee"
    end

    context "with an advance event fee" do
      let(:event_id) { SecureRandom.uuid }

      include_examples "a new interval fee"
    end

    context "with an advance transaction fee" do
      let(:transaction_id) { SecureRandom.uuid }

      include_examples "a new interval fee"
    end

    context "with a different fee type" do
      let(:fee_type) { :subscription }

      include_examples "a new interval fee"
    end

    context "with equivalent boundaries expressed in a different timezone" do
      let(:fee_from) { billing_segment.started_at.in_time_zone("Europe/Paris").iso8601(6) }
      let(:fee_to) { billing_segment.ended_at.in_time_zone("Europe/Paris").iso8601(6) }

      it "reuses the existing fee" do
        expect { result }.not_to change(Fee, :count)
        expect(result.fees).to eq([existing_fee])
      end
    end

    context "with current usage" do
      let(:options) { described_class::Options.new(context: :current_usage) }

      it "calculates fresh usage in memory" do
        expect { result }.not_to change(Fee, :count)
        expect(result.fees.sole).to be_new_record
        expect(result.fees.sole.amount_cents).to eq(400)
      end
    end

    context "with an invoice preview" do
      let(:options) { described_class::Options.new(context: :invoice_preview) }

      it "calculates the preview in memory" do
        expect { result }.not_to change(Fee, :count)
        expect(result.fees.sole).to be_new_record
        expect(result.fees.sole.amount_cents).to eq(400)
        expect(result.fees.sole.properties).to include(
          "from_datetime" => billing_segment.started_at.iso8601(6),
          "to_datetime" => billing_segment.ended_at.iso8601(6),
          "charges_from_datetime" => billing_segment.started_at.iso8601(6),
          "charges_to_datetime" => billing_segment.ended_at.iso8601(6)
        )
      end
    end
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
    billing_segment.ended_at = BillingSegment.inclusive_end(Time.utc(2026, 8, 15))
    first_fee = result.fees.sole
    later_segment = build(
      :billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
      currency: "USD", rate_properties: {"amount" => "3"}, cycle_started_at: billing_segment.cycle_started_at,
      started_at: Time.utc(2026, 8, 15), ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1)),
      proration_ratio: BigDecimal("1.0")
    )
    later_item = described_class::MeteredItem.from_billing_segment(billing_segment: later_segment)

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

    it "does not assign the legacy charge or expand its filters" do
      expect(result.fees.sole.reload).to have_attributes(
        invoiceable: product, fee_type: "product", charge_id: nil, charge_filter_id: nil, amount_cents: 400
      )
    end

    context "with a minimum amount" do
      let(:min_amount_cents) { 1000 }

      it "keeps the product fee and its true-up charge-less" do
        expect(result.fees.map(&:charge_id)).to eq([nil, nil])
        expect(result.fees.last.true_up_parent_fee).to eq(result.fees.first)
      end
    end
  end

  context "with a legacy add-on linked to the product" do
    let(:add_on) { create(:add_on, organization:) }
    let(:product) { create(:product, organization:, billable_metric:, add_on:) }

    it "keeps the product identity without creating a one-off add-on fee" do
      expect(result.fees.sole.reload).to have_attributes(
        invoiceable: product, fee_type: "product", add_on_id: nil, charge_id: nil,
        contract_rate_card:, amount_cents: 400
      )
    end

    context "with a minimum amount" do
      let(:min_amount_cents) { 1000 }

      it "keeps the product fee and true-up separate from one-off add-on fees" do
        expect(result.fees.map(&:add_on_id)).to eq([nil, nil])
        expect(result.fees.map(&:charge_id)).to eq([nil, nil])
      end
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
      expect(result.fees.sole.properties["product_filter_values"]).to be_nil
      expect(invoice.fees.pluck(:product_filter_id, :charge_filter_id)).to eq([[nil, nil]])
    end

    context "with a selected filter" do
      let(:product_filter) { eu_filter }

      it "only prices the rate card's selected bucket" do
        expect(result.fees.sole.reload).to have_attributes(product_filter_id: eu_filter.id, charge_filter_id: nil, units: 1, amount_cents: 200)
      end

      it "stores the selected filter values on the fee" do
        expect(result.fees.sole.reload.properties["product_filter_values"]).to eq("region" => ["eu"])
      end

      context "when the filter selects every value of a key" do
        let(:all_regions_filter) { create(:product_filter, organization:, product:) }
        let(:product_filter) { all_regions_filter }

        before do
          create(:product_filter_value, organization:, product_filter: all_regions_filter, billable_metric_filter: region, value: nil)
        end

        it "keeps the all-values marker" do
          expect(result.fees.sole.reload.properties["product_filter_values"]).to eq("region" => [nil])
        end
      end

      context "with a minimum amount" do
        let(:min_amount_cents) { 1000 }

        it "attaches the true-up to the scoped fee and clears its filter identity" do
          fees = result.fees

          expect(fees.map(&:amount_cents)).to eq([200, 800])
          expect(fees.first.product_filter_id).to eq(eu_filter.id)
          expect(fees.last).to have_attributes(
            invoiceable: product, fee_type: "product", product_filter_id: nil,
            charge_filter_id: nil, true_up_parent_fee: fees.first, contract:, contract_rate_card:
          )
          expect(fees.last.properties).not_to have_key("product_filter_values")
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

    it "persists the contract closing balance at the segment boundary" do
      expect { result }.to change(CachedAggregation, :count).by(1)
      expect(result).to be_success
      expect(result.fees.sole.amount_cents).to eq(400)
      expect(result.cached_aggregations.sole).to have_attributes(
        contract:, product:, charge_id: nil, product_filter_id: nil,
        current_aggregation: 2, timestamp: billing_segment.ended_at
      )
    end

    context "when the closing snapshot already exists alongside an event cache" do
      let!(:closing_snapshot) do
        create(
          :cached_aggregation,
          organization:,
          charge: nil,
          contract:,
          product:,
          external_subscription_id: contract.external_id,
          event_transaction_id: nil,
          timestamp: billing_segment.ended_at,
          current_aggregation: 1,
          current_amount: 50,
          presentation_breakdowns: [{groups: {region: "stale"}, units: 1}]
        )
      end
      let!(:event_cache) do
        create(
          :cached_aggregation,
          organization:,
          charge: nil,
          contract:,
          product:,
          external_subscription_id: contract.external_id,
          event_transaction_id: "event-cache-entry",
          timestamp: billing_segment.ended_at,
          current_aggregation: 100,
          current_amount: 75,
          presentation_breakdowns: [{groups: {region: "event"}, units: 100}]
        )
      end

      it "updates the closing snapshot without duplicating it or changing the event cache" do
        expect { result }.not_to change(CachedAggregation, :count)
        expect(result).to be_success
        expect(result.cached_aggregations).to eq([closing_snapshot])
        expect(closing_snapshot.reload).to have_attributes(
          current_aggregation: 2,
          current_amount: nil,
          presentation_breakdowns: []
        )
        expect(event_cache.reload).to have_attributes(
          current_aggregation: 100,
          current_amount: 75,
          presentation_breakdowns: [{"groups" => {"region" => "event"}, "units" => 100}]
        )
      end
    end

    context "with an invoice preview" do
      let(:options) { described_class::Options.new(context: :invoice_preview) }

      it "does not persist a closing snapshot" do
        expect { result }.not_to change(CachedAggregation, :count)
        expect(result.cached_aggregations).to be_nil
      end
    end

    context "with a renewal cutoff" do
      let(:metered_item) do
        described_class::MeteredItem.new(
          source: described_class::Sources::BillingSegment.new(
            billing_segment:,
            max_timestamp: BillingSegment.inclusive_end(billing_segment.started_at)
          )
        )
      end

      it "persists a closing snapshot when the charge context is not an advance renewal" do
        expect { result }.to change(CachedAggregation, :count).by(1)
        expect(result).to be_success
        expect(result.cached_aggregations.sole).to have_attributes(
          current_aggregation: 2,
          timestamp: billing_segment.ended_at
        )
      end

      context "with an advance-renewal context" do
        let(:options) { described_class::Options.new(context: :advance_renewal) }

        it "does not persist a closing snapshot" do
          expect { result }.not_to change(CachedAggregation, :count)
          expect(result).to be_success
          expect(result.cached_aggregations).to be_nil
        end
      end
    end
  end

  describe "recurring aggregation snapshots" do
    let(:organization) { create(:organization, feature_flags: ["recurring_aggregation_snapshots"]) }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 8, 1)) }
    let(:snapshots) { ContractRecurringAggregationSnapshot.where(contract:, product:) }
    let(:now) { Time.utc(2026, 9, 1, 1) }
    let(:watermark) { now - RecurringAggregationSnapshot::WATERMARK_LAG }

    around { |example| travel_to(now) { example.run } }

    before do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code,
        timestamp: Time.utc(2026, 7, 10), created_at: watermark - 1.minute, properties: {value: 4, region: "eu"})
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code,
        timestamp: Time.utc(2026, 8, 12), created_at: watermark - 1.minute, properties: {value: 6, region: "us"})
    end

    it "persists the cumulative units under the contract at the segment end" do
      expect(result.fees.sole.units).to eq(10) # 4 from July + 6 from August, recurring
      expect(snapshots.sole).to have_attributes(
        organization_id: organization.id,
        product_filter_id: nil,
        billable_metric_id: billable_metric.id,
        grouped_by: {},
        to_datetime: billing_segment.ended_at,
        watermark:,
        units: 10,
        events_count: 2,
        presentation_breakdowns: [],
        priced_product_filter_ids: []
      )
      expect(RecurringAggregationSnapshot.count).to eq(0)
    end

    context "without the recurring_aggregation_snapshots feature flag" do
      let(:organization) { create(:organization) }

      it "bills the units without persisting snapshots" do
        expect(result.fees.sole.units).to eq(10)
        expect(snapshots).to be_empty
      end
    end

    context "with a weighted sum metric" do
      let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:, field_name: "value") }

      it "persists the units at the segment end" do
        expect(result).to be_success
        expect(snapshots.sole).to have_attributes(units: 10, to_datetime: billing_segment.ended_at)
      end
    end

    context "with pricing group keys" do
      let(:rate_properties) { {"amount" => "2", "pricing_group_keys" => ["region"]} }

      it "persists one snapshot per group" do
        expect(result).to be_success
        expect(snapshots.pluck(:grouped_by, :units, :events_count)).to contain_exactly([{"region" => "eu"}, 4, 1], [{"region" => "us"}, 6, 1])
      end
    end

    context "with a rate card scoped to a product filter" do
      let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
      let(:eu_filter) { create(:product_filter, organization:, product:) }
      let(:us_filter) { create(:product_filter, organization:, product:) }
      let(:product_filter) { eu_filter }

      before do
        create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
        create(:product_filter_value, organization:, product_filter: us_filter, billable_metric_filter: region, value: "us")
      end

      it "persists the filter's bucket and the filters priced in the segment" do
        expect(result).to be_success
        expect(snapshots.sole).to have_attributes(product_filter_id: eu_filter.id, units: 4, events_count: 1, priced_product_filter_ids: [eu_filter.id])
      end

      context "with another priced filter of the product" do
        before do
          create(:contract_rate_card, organization:, contract:, effective_date: Date.new(2026, 8, 1),
            rate_card: create(:rate_card, organization:, product:, product_filter: us_filter, currency: "USD"))
        end

        it "stores every priced filter of the product" do
          expect(result).to be_success
          expect(snapshots.sole.priced_product_filter_ids).to eq([eu_filter.id, us_filter.id].sort)
        end
      end

      context "without events in the bucket" do
        let(:product_filter) { us_filter }

        before { Event.where(organization:).where("properties->>'region' = 'us'").delete_all }

        it "persists a zero units snapshot as the marker of the period" do
          expect(result).to be_success
          expect(snapshots.pluck(:product_filter_id, :grouped_by, :units)).to eq([[us_filter.id, {}, 0]])
        end
      end
    end

    context "without events" do
      before { Event.where(organization:).delete_all }

      it "persists a zero units snapshot as the marker of the period" do
        expect(result).to be_success
        expect(snapshots.pluck(:product_filter_id, :units, :events_count)).to eq([[nil, 0, 0]])
      end
    end

    context "with an advance renewal" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, product_filter:, currency: "USD") }
      let(:metered_item) do
        described_class::MeteredItem.from_billing_segment(billing_segment:, max_timestamp: BillingSegment.inclusive_end(billing_segment.started_at))
      end
      let(:options) { described_class::Options.new(context: :advance_renewal) }

      it "bills the units up to the segment start without persisting snapshots" do
        expect(result.fees.sole.units).to eq(4)
        expect(snapshots).to be_empty
      end
    end

    context "with a max timestamp" do
      let(:metered_item) do
        described_class::MeteredItem.from_billing_segment(billing_segment:, max_timestamp: Time.utc(2026, 8, 5))
      end

      it "persists no snapshot, as the units stop before the segment end" do
        expect(result.fees.sole.units).to eq(4)
        expect(snapshots).to be_empty
      end
    end

    context "with current usage" do
      let(:invoice) { nil }
      let(:options) { described_class::Options.new(context: :current_usage) }

      it "persists no snapshot" do
        expect(result).to be_success
        expect(snapshots).to be_empty
      end
    end

    context "with an invoice preview" do
      let(:options) { described_class::Options.new(context: :invoice_preview) }

      it "persists no snapshot" do
        expect(result).to be_success
        expect(snapshots).to be_empty
      end
    end

    context "with a count metric" do
      let(:billable_metric) { create(:billable_metric, :recurring, organization:, aggregation_type: :unique_count_agg, field_name: "value") }

      it "persists no snapshot" do
        expect(result).to be_success
        expect(snapshots).to be_empty
      end
    end

    context "with a snapshot of the previous segment" do
      let(:organization) { create(:organization, feature_flags: %w[recurring_aggregation_snapshots persisted_recurring_values]) }
      let(:previous_watermark) { watermark - 30.seconds } # after both events were ingested
      let(:previous_priced_ids) { [] }
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 8, 1), created_at: previous_watermark - 1.day)
      end

      before do
        create(:contract_recurring_aggregation_snapshot, organization:, contract:, product:, product_filter:, units: 100,
          events_count: 1, to_datetime: BillingSegment.inclusive_end(billing_segment.started_at), watermark: previous_watermark,
          priced_product_filter_ids: previous_priced_ids)
      end

      it "bills the snapshot units plus the events after it, and persists them at the segment end" do
        expect(result.fees.sole.units).to eq(100 + 6) # snapshot + August event
        expect(snapshots.order(:to_datetime).last).to have_attributes(to_datetime: billing_segment.ended_at, units: 106, events_count: 2)
      end

      context "with an event dated in the snapshot period and ingested after its watermark" do
        before do
          create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code,
            timestamp: Time.utc(2026, 7, 20), created_at: previous_watermark + 1.second, properties: {value: 3})
        end

        it "adds the late event to the snapshot units" do
          expect(result.fees.sole.units).to eq(100 + 3 + 6) # snapshot + late July event + August event
        end
      end

      context "without the persisted_recurring_values feature flag" do
        let(:organization) { create(:organization, feature_flags: ["recurring_aggregation_snapshots"]) }

        it "reads the full history" do
          expect(result.fees.sole.units).to eq(4 + 6)
        end
      end

      context "with current usage" do
        let(:invoice) { nil }
        let(:options) { described_class::Options.new(context: :current_usage) }

        it "reads the snapshot" do
          expect(result.fees.sole.units).to eq(100 + 6)
        end
      end

      context "when the period was closed with other priced filters" do
        let(:previous_priced_ids) { [create(:product_filter, organization:, product:, created_at: previous_watermark - 1.day).id] }

        it "reads the full history" do
          expect(result.fees.sole.units).to eq(4 + 6)
        end
      end

      context "when a rate card of the product was added to the contract since the snapshot" do
        # The filter predates the snapshot and the card starts before the segment, so only the card changed since it
        before do
          create(:contract_rate_card, organization:, contract:, effective_date: Date.new(2026, 7, 1),
            rate_card: create(:rate_card, organization:, product:, currency: "USD",
              product_filter: create(:product_filter, organization:, product:, created_at: previous_watermark - 1.day)))
        end

        it "reads the full history" do
          expect(result.fees.sole.units).to eq(4 + 6)
        end
      end

      context "with two priced filters of the product" do
        let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
        let(:eu_filter) { create(:product_filter, organization:, product:, created_at: previous_watermark - 1.day) }
        let(:us_filter) { create(:product_filter, organization:, product:, created_at: previous_watermark - 1.day) }
        let(:product_filter) { eu_filter }
        let(:previous_priced_ids) { [eu_filter.id, us_filter.id].sort }

        before do
          [[eu_filter, "eu"], [us_filter, "us"]].each do |filter, value|
            create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: region, value:,
              created_at: previous_watermark - 1.day, updated_at: previous_watermark - 1.day)
          end
          create(:contract_rate_card, organization:, contract:, effective_date: Date.new(2026, 8, 1), created_at: previous_watermark - 1.day,
            rate_card: create(:rate_card, organization:, product:, product_filter: us_filter, currency: "USD"))
        end

        it "reads the snapshot of the filter's bucket" do
          expect(result.fees.sole.units).to eq(100) # snapshot, the August event being in the us bucket
        end

        context "when the period was closed with only the filter priced" do
          let(:previous_priced_ids) { [eu_filter.id] }

          it "reads the full history" do
            expect(result.fees.sole.units).to eq(4) # July eu event
          end
        end
      end

      context "with a weighted sum metric" do
        let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:, field_name: "value") }

        it "starts from the snapshot units" do
          # 100 for the 11 days before the August event, 106 for the 20 days after it, over 31 days
          expect(result.fees.sole.units.round(5)).to eq(BigDecimal("103.87097")) # (100 * 11 + 106 * 20) / 31
        end
      end

      context "with a prorated rate card" do
        let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "USD", proration: true) }

        it "bills the snapshot units for the whole segment and the event from its date" do
          fee = result.fees.sole
          expect(fee.units).to eq(100 + 6) # snapshot + August event
          expect(fee.precise_amount_cents.round(3)).to eq(BigDecimal("20774.194")) # 2 USD * (100 + 6 * 20 / 31) units, the August event over 20 of 31 days
        end

        context "with a partial segment" do
          let(:proration_ratio) { BigDecimal("0.5") }

          it "applies the segment ratio to the snapshot units" do
            # 2 USD * 0.5 * (100 + 6 * 20 / 31) units, units ceiled to 5 decimals; the full scan bills from 4 instead of 100
            expect(result.fees.sole.precise_amount_cents.round(3)).to eq(BigDecimal("10387.098"))
          end
        end
      end
    end
  end

  context "with a minimum amount" do
    let(:min_amount_cents) { 1000 }

    it "uses the segment proration ratio" do
      billing_segment.proration_ratio = 0.5

      expect(result.fees.map(&:amount_cents)).to eq([400, 100])
      expect(result.fees.last).to have_attributes(fee_type: "product", rate_card_rate:, true_up_parent_fee: result.fees.first)
    end

    it "does not create a true-up at or above the minimum" do
      billing_segment.rate_properties = {"amount" => "5"}

      expect(result.fees.sole.amount_cents).to eq(1000)
    end

    it "bills the minimum even when no events match" do
      billing_segment.started_at = Time.utc(2026, 8, 25)

      expect(result.fees.map(&:amount_cents)).to eq([0, 1000])
    end

    it "uses the override minimum and preserves pricing identity" do
      override = create(:rate_override, organization:, min_amount_cents: 1400)
      billing_segment.rate_override = override
      billing_segment.proration_ratio = 0.5

      expect(result.fees.map(&:amount_cents)).to eq([400, 300])
      expect(result.fees.map(&:rate_override)).to eq([override, override])
    end

    context "with pricing units" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", applied_pricing_unit_code: pricing_unit.code) }
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, min_amount_cents:, applied_pricing_unit_conversion_rate: 0.5)
      end

      before { billing_segment.proration_ratio = 0.5 }

      it "converts the prorated minimum and usage with the segment conversion rate" do
        expect(result.fees.map(&:amount_cents)).to eq([200, 300])
        expect(result.fees.map { |fee| fee.pricing_unit_usage.amount_cents }).to eq([400, 600])
        expect(result.fees.last.pricing_unit_usage).to have_attributes(pricing_unit:, conversion_rate: 0.5)
      end

      it "uses the override conversion rate rather than the catalog rate" do
        override = create(:rate_override, organization:, min_amount_cents: 1000, pricing_unit_conversion_rate: 0.25)
        billing_segment.rate_override = override

        expect(result.fees.map(&:amount_cents)).to eq([100, 400])
        expect(result.fees.map { |fee| fee.pricing_unit_usage.conversion_rate }).to eq([0.25, 0.25])
      end
    end
  end
end
