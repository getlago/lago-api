# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::PercentageService do
  subject(:apply_percentage_service) do
    described_class.apply(
      pricing_structure:,
      aggregation_result:,
      period_ratio: 1.0
    )
  end

  before do
    aggregation_result.aggregation = aggregation
    aggregation_result.count = 4
    aggregation_result.options = {running_total:}
  end

  let(:running_total) { [50, 150, 400] }
  let(:pricing_structure) { ChargeModels::PricingStructure.from_charge(charge) }
  let(:charge) do
    create(
      :percentage_charge,
      organization:,
      plan:,
      properties: {
        rate:,
        fixed_amount:,
        free_units_per_events:,
        free_units_per_total_aggregation:,
        per_transaction_max_amount:,
        per_transaction_min_amount:
      }
    )
  end
  let(:aggregation_result) { BillableMetrics::Aggregations::BaseService::Result.new }
  let(:fixed_amount) { "2.0" }
  let(:aggregation) { 800 }
  let(:free_units_per_events) { 3 }
  let(:free_units_per_total_aggregation) { "250.0" }
  let(:per_transaction_max_amount) { nil }
  let(:per_transaction_min_amount) { nil }

  let(:rate) { "1.3" }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:plan, refind: true) { create(:plan, organization:) }

  before_all do
    create_default(:customer)
  end

  context "when aggregation value is 0" do
    let(:aggregation) { 0 }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(0)
      expect(apply_percentage_service.unit_amount).to eq(0)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "0.0",
          free_units: "250.0",
          paid_units: "0.0",
          free_events: 2,
          rate: 1.3,
          per_unit_total_amount: 0,
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "0.0",
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when fixed amount value is 0" do
    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(11.15)
      expect(apply_percentage_service.unit_amount).to eq(0.0139375) # 11.15 / 800
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "250.0",
          paid_units: "550.0",
          free_events: 2,
          rate: 1.3,
          per_unit_total_amount: 7.15, # (800 - 250) * (1.3 / 100),
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "4.0", # (4 - 2) * 2.0
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "with small units amount" do
    let(:running_total) { [] }
    let(:fixed_amount) { nil }
    let(:aggregation) { 4 }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { nil }
    let(:per_transaction_max_amount) { nil }
    let(:per_transaction_min_amount) { nil }
    let(:rate) { "2.9" }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(0.116)
      expect(apply_percentage_service.unit_amount).to eq(0.029) # 0.116 / 4
      expect(apply_percentage_service.amount_details).to match hash_including(
        units: "4.0",
        paid_units: "4.0",
        rate: 2.9,
        per_unit_total_amount: 0.116, # 4 * 0.029
        paid_events: 4
      )
    end
  end

  context "when rate is 0" do
    let(:running_total) { [] }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { nil }
    let(:rate) { "0" }
    let(:expected_fixed_amount) { (4 - 0) * 2.0 }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(8)
      expect(apply_percentage_service.unit_amount).to eq(0.01)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "0.0",
          paid_units: "800.0",
          free_events: 0,
          rate: 0,
          per_unit_total_amount: 0,
          paid_events: 4,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "8.0",
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when free_units_per_events is nil" do
    let(:free_units_per_events) { nil }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(11.15) # (800 - 250) * (1.3 / 100) + (4 - 2) * 2.0
      expect(apply_percentage_service.unit_amount).to eq(0.0139375)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "250.0",
          paid_units: "550.0",
          free_events: 2,
          rate: 1.3,
          per_unit_total_amount: 7.15,
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "4.0",
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when free_units_per_total_aggregation is nil" do
    let(:free_units_per_total_aggregation) { nil }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(7.2)
      expect(apply_percentage_service.unit_amount).to eq(0.009)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "400.0",
          paid_units: "400.0",
          free_events: 3,
          rate: 1.3,
          per_unit_total_amount: 5.2, # (800 - 400) * (1.3 / 100)
          paid_events: 1,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "2.0", # (4 - 3) * 2.0
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when free units are not set" do
    let(:free_units_per_total_aggregation) { nil }
    let(:free_units_per_events) { nil }
    let(:running_total) { [] }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(18.4)
      expect(apply_percentage_service.unit_amount).to eq(0.023)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "0.0",
          paid_units: "800.0",
          free_events: 0,
          rate: 1.3,
          per_unit_total_amount: 10.4, # 800 * (1.3 / 100)
          paid_events: 4,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "8.0", # 4 * 2.0
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when free_units_per_total_aggregation > last running total" do
    let(:free_units_per_total_aggregation) { "500.0" }
    let(:expected_percentage_amount) { (800 - 400) * (1.3 / 100) }
    let(:expected_fixed_amount) { (4 - 3) * 2.0 }

    it "returns expected amount" do
      expect(apply_percentage_service.amount).to eq(7.2)
      expect(apply_percentage_service.unit_amount).to eq(0.009)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: "800.0",
          free_units: "400.0",
          paid_units: "400.0",
          free_events: 3,
          rate: 1.3,
          per_unit_total_amount: 5.2, # (800 - 400) * (1.3 / 100)
          paid_events: 1,
          fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "2.0", # (4 - 3) * 2.0
          min_max_adjustment_total_amount: "0.0"
        }
      )
    end
  end

  context "when free_units_count > number of events" do
    let(:free_units_per_events) { 5 }
    let(:free_units_per_total_aggregation) { nil }
    let(:aggregation) { 400 }

    it "returns 0" do
      expect(apply_percentage_service.amount).to eq(0)
    end
  end

  context "with a catalog maximum closing value", :premium do
    let(:pricing_structure) { super().with(product_catalog: true) }
    let(:aggregation) { 3 }
    let(:closing_units) { 10 }
    let(:event_values) { [closing_units || aggregation] }
    let(:running_total) { [] }
    let(:fixed_amount) { "0" }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { "0" }
    let(:per_transaction_min_amount) { "0.01" }
    let(:rate) { "10" }
    let(:per_event_aggregation) do
      BillableMetrics::Aggregations::BaseService::PerEventAggregationResult.new.tap { it.event_aggregation = event_values }
    end
    let(:aggregator) { instance_double(BillableMetrics::Aggregations::MaxService, per_event_aggregation:) }

    before do
      aggregation_result.closing_units = closing_units
      aggregation_result.count = event_values.size
      aggregation_result.aggregator = aggregator
    end

    it "prices the closing maximum without changing the local aggregation" do
      expect(apply_percentage_service).to have_attributes(amount: 1, units: 10, count: 1) # $10 × 10%.
      expect(aggregation_result.aggregation).to eq(3)
      expect(aggregator).to have_received(:per_event_aggregation).with(
        exclude_event: nil, include_event_value: nil, grouped_by_values: nil, closing_units: 10
      )
    end

    context "with an observed zero" do
      let(:aggregation) { 0 }

      it "retains the carried maximum" do
        expect(apply_percentage_service.amount).to eq(1) # $10 × 10%.
      end
    end

    context "with a fixed fee" do
      let(:fixed_amount) { "2" }

      it "charges the fixed fee only for the real event" do
        expect(apply_percentage_service.amount).to eq(1 + 2) # $10 × 10% + one event's $2 fixed fee.
      end
    end

    context "with one free event" do
      let(:free_units_per_events) { 1 }

      it "keeps the real event's allowance" do
        expect(apply_percentage_service.amount).to eq(0)
      end

      context "when the local maximum is negative" do
        let(:event_values) { [10, 0] }
        let(:aggregation) { -3 }

        it "keeps the closing maximum on the original maximum's event" do
          expect(apply_percentage_service.amount).to eq(BigDecimal("0.01")) # The first event is free; the other has the $0.01 minimum.
        end
      end
    end

    context "without product catalog pricing" do
      let(:pricing_structure) { ChargeModels::PricingStructure.from_charge(charge) }

      it "prices the closing maximum" do
        expect(apply_percentage_service.amount).to eq(1) # Closing $10 × 10%.
      end
    end

    context "without a closing maximum" do
      let(:closing_units) { nil }

      it "keeps the existing local per-event calculation" do
        expect(apply_percentage_service.amount).to eq(BigDecimal("0.3")) # Local $3 × 10%.
      end
    end

    context "with a monetary free allowance" do
      let(:free_units_per_total_aggregation) { "5" }
      let(:expected_amount) { BigDecimal("0.5") }
      let(:expected_details) do
        {
          units: "10.0", free_units: "5.0", free_events: 0, paid_units: "5.0", rate: 10,
          per_unit_total_amount: BigDecimal("0.5"), paid_events: 1, fixed_fee_unit_amount: 0,
          fixed_fee_total_amount: "0.0", min_max_adjustment_total_amount: "0.0"
        }
      end

      shared_examples "accounts for the monetary allowance" do
        it "reports the allowance separately from transaction limit adjustments" do
          expect(apply_percentage_service.amount).to eq(expected_amount)
          expect(apply_percentage_service.amount_details).to eq(expected_details)
        end
      end

      include_examples "accounts for the monetary allowance"

      context "without transaction limits" do
        let(:per_transaction_min_amount) { nil }

        include_examples "accounts for the monetary allowance"

        context "without local events" do
          let(:event_values) { [] }
          let(:aggregation) { 0 }
          let(:expected_details) { super().merge(paid_events: 0) }

          include_examples "accounts for the monetary allowance"
        end

        context "with legacy Sum running totals" do
          let(:pricing_structure) { ChargeModels::PricingStructure.from_charge(charge) }
          let(:closing_units) { nil }
          let(:aggregation) { 10 }
          let(:running_total) { [10] }

          include_examples "accounts for the monetary allowance"

          it "does not query the per-event aggregation" do
            apply_percentage_service

            expect(aggregator).not_to have_received(:per_event_aggregation)
          end
        end
      end

      context "without a premium license" do
        let(:per_transaction_min_amount) { "2" }

        before { allow(License).to receive(:premium?).and_return(false) }

        include_examples "accounts for the monetary allowance"
      end

      context "when the allowance equals the maximum" do
        let(:free_units_per_total_aggregation) { "10" }
        let(:expected_amount) { BigDecimal("0.01") }
        let(:expected_details) do
          super().merge(free_units: "10.0", paid_units: "0.0", per_unit_total_amount: 0, min_max_adjustment_total_amount: "0.01")
        end

        include_examples "accounts for the monetary allowance"
      end

      context "when the allowance exceeds the maximum" do
        let(:free_units_per_total_aggregation) { "11" }
        let(:expected_amount) { 0 }
        let(:expected_details) do
          super().merge(free_units: "10.0", free_events: 1, paid_units: "0.0", per_unit_total_amount: 0, paid_events: 0)
        end

        include_examples "accounts for the monetary allowance"
      end

      context "without local events" do
        let(:event_values) { [] }
        let(:aggregation) { 0 }
        let(:expected_details) { super().merge(paid_events: 0) }

        include_examples "accounts for the monetary allowance"

        context "when the allowance equals the maximum" do
          let(:free_units_per_total_aggregation) { "10" }
          let(:expected_amount) { BigDecimal("0.01") }
          let(:expected_details) do
            super().merge(free_units: "10.0", paid_units: "0.0", per_unit_total_amount: 0, min_max_adjustment_total_amount: "0.01")
          end

          include_examples "accounts for the monetary allowance"
        end

        context "when the allowance exceeds the maximum" do
          let(:free_units_per_total_aggregation) { "11" }
          let(:expected_amount) { 0 }
          let(:expected_details) do
            super().merge(free_units: "10.0", paid_units: "0.0", per_unit_total_amount: 0)
          end

          include_examples "accounts for the monetary allowance"
        end
      end
    end

    context "without allowances or transaction limits" do
      let(:per_transaction_min_amount) { nil }

      it "prices the closing maximum without querying the per-event aggregation" do
        expect(apply_percentage_service.amount).to eq(1) # $10 × 10%.
        expect(aggregator).not_to have_received(:per_event_aggregation)
      end
    end

    context "with a free event allowance but no transaction limits" do
      let(:per_transaction_min_amount) { nil }
      let(:free_units_per_events) { 1 }

      it "reports the free real event and its closing units" do
        expect(apply_percentage_service.amount).to eq(0)
        expect(apply_percentage_service.amount_details).to eq(
          units: "10.0", free_units: "10.0", free_events: 1, paid_units: "0.0", rate: 10,
          per_unit_total_amount: 0, paid_events: 0, fixed_fee_unit_amount: 0,
          fixed_fee_total_amount: "0.0", min_max_adjustment_total_amount: "0.0"
        )
      end
    end

    context "with zero closing units and a fixed fee" do
      let(:closing_units) { 0 }
      let(:fixed_amount) { "2" }

      it "reports the real event's fixed fee separately from transaction limit adjustments" do
        expect(apply_percentage_service.amount).to eq(2)
        expect(apply_percentage_service.amount_details).to eq(
          units: "0.0", free_units: "0.0", free_events: 0, paid_units: "0.0", rate: 10,
          per_unit_total_amount: 0, paid_events: 1, fixed_fee_unit_amount: 2,
          fixed_fee_total_amount: "2.0", min_max_adjustment_total_amount: "0.0"
        )
      end
    end

    context "without local events" do
      let(:event_values) { [] }
      let(:aggregation) { 0 }

      it "prices the carried maximum without creating a paid event" do
        expect(apply_percentage_service).to have_attributes(amount: 1, units: 10, count: 0)
        expect(apply_percentage_service.amount_details).to eq(
          units: "10.0", free_units: "0.0", free_events: 0, paid_units: "10.0", rate: 10,
          per_unit_total_amount: 1, paid_events: 0, fixed_fee_unit_amount: 0,
          fixed_fee_total_amount: "0.0", min_max_adjustment_total_amount: "0.0"
        )
      end

      context "with a binding minimum" do
        let(:per_transaction_min_amount) { "2" }

        it "applies the minimum once to the percentage amount" do
          expect(apply_percentage_service.amount).to eq(2)
          expect(apply_percentage_service.amount_details[:min_max_adjustment_total_amount]).to eq("1.0") # $2 minimum - $1 percentage.
        end
      end

      context "with a binding maximum" do
        let(:per_transaction_max_amount) { "0.50" }

        it "applies the maximum once to the percentage amount" do
          expect(apply_percentage_service.amount).to eq(BigDecimal("0.5"))
          expect(apply_percentage_service.amount_details[:min_max_adjustment_total_amount]).to eq("-0.5") # $0.50 cap - $1 percentage.
        end
      end

      context "with a fixed fee" do
        let(:fixed_amount) { "2" }

        it "does not charge a fixed fee for the carried maximum" do
          expect(apply_percentage_service.amount).to eq(1)
          expect(apply_percentage_service.amount_details[:fixed_fee_total_amount]).to eq("0.0")
        end
      end

      context "with a free event allowance" do
        let(:free_units_per_events) { 1 }

        it "does not consume an event allowance for the carried maximum" do
          expect(apply_percentage_service.amount).to eq(1)
          expect(apply_percentage_service.amount_details[:free_events]).to eq(0)
        end
      end

      context "with a zero closing maximum" do
        let(:closing_units) { 0 }

        it "does not create a minimum fee for zero usage and no events" do
          expect(apply_percentage_service.amount).to eq(0)
        end
      end
    end
  end

  context "when applying min / max amount per transaction" do
    let(:per_transaction_max_amount) { "12" }
    let(:metered_item) do
      Fees::ChargeService::MeteredItem.from_charge(
        charge:,
        boundaries: BillingPeriodBoundaries.new(
          from_datetime: subscription.started_at,
          to_datetime: subscription.started_at.end_of_month,
          charges_from_datetime: subscription.started_at,
          charges_to_datetime: subscription.started_at.end_of_month,
          charges_duration: subscription.started_at.end_of_month.day - subscription.started_at.day + 1,
          timestamp: subscription.started_at.end_of_month
        )
      )
    end
    let(:aggregator) do
      BillableMetrics::Aggregations::SumService.new(
        event_store: event_store_class.new(billing_context:, boundaries: nil),
        metered_item:,
        billing_context:,
        boundaries: nil
      )
    end
    let(:billing_context) { Billing::Context.from(subscription:) }
    let(:event_store_class) { Events::Stores::PostgresStore }
    let(:aggregation) { 10_090 }
    let(:fixed_amount) { "0" }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { "0" }
    let(:rate) { "2.99" }
    let(:per_event_aggregation) { BillableMetrics::Aggregations::BaseService::PerEventAggregationResult.new.tap { |r| r.event_aggregation = [10, 80, 10_000] } }
    let(:running_total) { [] }
    let(:per_transaction_min_amount) { "1.75" }

    let_it_be(:subscription, refind: true) { create(:subscription, organization:, plan:) }

    before do
      aggregation_result.aggregator = aggregator
      aggregation_result.count = 3

      allow(aggregator).to receive(:per_event_aggregation).and_return(per_event_aggregation)
    end

    it "does not apply max and min if not premium" do
      expect(apply_percentage_service.amount).to eq(301.691) # (10 + 80 + 10000) * 0.0299
    end

    context "when premium", :premium do
      it "applies the min and max per transaction" do
        # 1.75 (min as 10 * 0.0299 < 1.75) + 2.392 + 12 (max as 10000 * 0.0299 > 12)
        expect(apply_percentage_service.amount).to eq(16.142)
      end

      context "with fixed_amount" do
        let(:fixed_amount) { "2.0" }

        it "applies the min and max per transaction" do
          # 2.299 (10 * 0.0299 + 2 > 1.75) + 4.392 + 12 (max as 10000 * 0.0299 > 12)
          expect(apply_percentage_service.amount).to eq(18.691)
        end
      end

      context "with free units per events" do
        let(:free_units_per_events) { 2 }

        it "applies the min and max only on paying transaction" do
          # 10000 * 0.01 > 12
          expect(apply_percentage_service.amount).to eq(12)
        end
      end

      context "with free units per total aggregation" do
        let(:free_units_per_total_aggregation) { "30" }

        it "takes the free amount into account" do
          # 1.794 ((10 + 80 - 40) * 0.0299) + 12 (max as 10000 * 0.0299 > 12)
          expect(apply_percentage_service.amount).to eq(13.794)
        end
      end

      context "when both free units per events and per total aggregation are applied" do
        let(:free_units_per_events) { 3 }
        let(:free_units_per_total_aggregation) { "10000" }

        it "takes the free amounts into account" do
          # (10 + 80 + 10000 - 10000) * 0.0299
          expect(apply_percentage_service.amount).to eq(2.691)
        end
      end
    end
  end
end
