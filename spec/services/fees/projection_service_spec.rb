# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ProjectionService do
  subject(:service) { described_class.new(fees: fees) }

  let(:fees) { [fee] }
  let(:fee) do
    instance_double(
      "Fee",
      charge: charge,
      subscription: subscription,
      charge_filter: charge_filter,
      properties: fee_properties
    )
  end

  let(:billable_metric) do
    instance_double(
      "BillableMetric",
      recurring?: false
    )
  end

  let(:charge) do
    instance_double(
      "Charge",
      id: SecureRandom.uuid,
      properties: charge_properties,
      applied_pricing_unit: applied_pricing_unit,
      filters: [],
      pricing_group_keys: nil,
      billable_metric: billable_metric
    )
  end

  let(:subscription) do
    instance_double(
      "Subscription",
      plan: plan
    )
  end

  let(:plan) do
    instance_double(
      "Plan",
      amount: amount
    )
  end

  let(:amount) do
    instance_double(
      "Money",
      currency: currency
    )
  end

  let(:currency) do
    instance_double(
      "Currency",
      exponent: 2,
      subunit_to_unit: 100
    )
  end

  let(:charge_filter) { nil }
  let(:applied_pricing_unit) { nil }
  let(:charge_properties) { {} }

  let(:fee_properties) do
    {
      "from_datetime" => from_datetime,
      "to_datetime" => to_datetime,
      "charges_duration" => charges_duration
    }
  end

  let(:from_datetime) { Time.current.beginning_of_month }
  let(:to_datetime) { Time.current.end_of_month }
  let(:charges_duration) { nil }

  let(:aggregation_result) do
    instance_double(
      "AggregationResult",
      success?: true,
      error: nil
    )
  end

  let(:charge_model_result) do
    instance_double(
      "ChargeModelResult",
      success?: true,
      error: nil,
      projected_amount: BigDecimal("100.50"),
      projected_units: BigDecimal(10),
      unit_amount: BigDecimal("10.05")
    )
  end

  before do
    allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_return(
      instance_double("Aggregator", aggregate: aggregation_result)
    )

    allow(ChargeModels::Factory).to receive(:new_instance).and_return(
      instance_double("ChargeModel", apply: charge_model_result)
    )

    middle_time = from_datetime + ((to_datetime - from_datetime) / 2)
    travel_to(middle_time)
  end

  after do
    travel_back
  end

  describe "#call" do
    context "when aggregation fails" do
      let(:aggregation_result) do
        instance_double(
          "AggregationResult",
          success?: false,
          error: StandardError.new("Aggregation failed")
        )
      end

      it "returns failure with aggregation error" do
        result = service.call

        expect(result).to be_failure
        expect(result.error).to be_a(StandardError)
        expect(result.error.message).to eq("Aggregation failed")
      end
    end

    context "when charge model fails" do
      let(:charge_model_result) do
        instance_double(
          "ChargeModelResult",
          success?: false,
          error: StandardError.new("Charge model failed")
        )
      end

      it "returns failure with charge model error" do
        result = service.call

        expect(result).to be_failure
        expect(result.error).to be_a(StandardError)
        expect(result.error.message).to eq("Charge model failed")
      end
    end

    context "when everything succeeds" do
      it "returns projected values" do
        result = service.call

        expect(result).to be_success
        expect(result.projected_amount_cents).to eq(10050) # 100.50 * 100
        expect(result.projected_units).to eq(BigDecimal(10))
        expect(result.projected_pricing_unit_amount_cents).to eq(nil) # No applied_pricing_unit
      end

      it "calls aggregation with correct parameters" do
        aggregator = instance_double("Aggregator", aggregate: aggregation_result)
        allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_return(aggregator)
        service.call
        expect(BillableMetrics::AggregationFactory).to have_received(:new_instance).with(
          charge: charge,
          subscription: subscription,
          boundaries: {
            from_datetime: from_datetime.to_date,
            to_datetime: to_datetime.to_date,
            charges_duration: charges_duration
          },
          filters: {charge_id: charge.id},
          current_usage: true
        )
        expect(aggregator).to have_received(:aggregate).with(options: {is_current_usage: true})
      end

      it "calls charge model factory with correct parameters" do
        from_date = from_datetime.to_date
        to_date = to_datetime.to_date
        current_date = Time.current.to_date

        total_days = (to_date - from_date).to_i + 1
        days_passed = (current_date - from_date).to_i + 1
        expected_period_ratio = days_passed.fdiv(total_days)

        service.call

        expect(ChargeModels::Factory).to have_received(:new_instance).with(
          chargeable: charge,
          aggregation_result:,
          properties: charge_properties,
          period_ratio: expected_period_ratio,
          calculate_projected_usage: true
        )
      end
    end

    context "with charge filter" do
      let(:charge_filter) do
        instance_double(
          "ChargeFilter",
          properties: {"key" => "value"},
          pricing_group_keys: []
        )
      end

      let(:filter_service_result) do
        instance_double(
          "FilterServiceResult",
          matching_filters: ["filter1"],
          ignored_filters: ["filter2"]
        )
      end

      before do
        allow(ChargeFilters::MatchingAndIgnoredService).to receive(:call)
          .and_return(filter_service_result)
      end

      it "uses charge filter properties and filters" do
        allow(service).to receive(:period_ratio).and_return(0.5) # rubocop:disable RSpec/SubjectStub
        aggregator = instance_double("Aggregator", aggregate: aggregation_result)
        allow(BillableMetrics::AggregationFactory).to receive(:new_instance).and_return(aggregator)
        service.call
        expect(BillableMetrics::AggregationFactory).to have_received(:new_instance).with(
          charge: charge,
          subscription: subscription,
          boundaries: {
            from_datetime: from_datetime.to_date,
            to_datetime: to_datetime.to_date,
            charges_duration: charges_duration
          },
          filters: {
            charge_id: charge.id,
            charge_filter: charge_filter,
            matching_filters: ["filter1"],
            ignored_filters: ["filter2"]
          },
          current_usage: true
        )

        expect(ChargeModels::Factory).to have_received(:new_instance).with(
          chargeable: charge,
          aggregation_result:,
          properties: {"key" => "value"},
          period_ratio: 0.5,
          calculate_projected_usage: true
        )

        service.call
      end
    end

    context "with applied pricing unit" do
      let(:applied_pricing_unit) { instance_double("AppliedPricingUnit") }
      let(:pricing_unit_usage) do
        instance_double(
          "PricingUnitUsage",
          to_fiat_currency_cents: {amount_cents: 5000}
        )
      end

      before do
        allow(PricingUnitUsage).to receive(:build_from_fiat_amounts)
          .and_return(pricing_unit_usage)
      end

      it "calculates projected pricing unit amount cents" do
        result = service.call

        expect(result).to be_success
        expect(result.projected_pricing_unit_amount_cents).to eq(5000)

        expect(PricingUnitUsage).to have_received(:build_from_fiat_amounts).with(
          amount: BigDecimal("100.50"),
          unit_amount: BigDecimal("10.05"),
          applied_pricing_unit: applied_pricing_unit
        )
      end
    end
  end

  describe "period_ratio calculation" do
    let(:from_date) { Date.current.beginning_of_month }
    let(:to_date) { Date.current.end_of_month }
    let(:from_datetime) { from_date.beginning_of_day }
    let(:to_datetime) { to_date.end_of_day }

    context "when current date is in the middle of period" do
      before { travel_to(from_date + 10.days) }

      it "calculates correct ratio" do
        from_date_calc = from_datetime.to_date
        to_date_calc = to_datetime.to_date
        current_date_calc = Time.current.to_date

        total_days = (to_date_calc - from_date_calc).to_i + 1
        days_passed = (current_date_calc - from_date_calc).to_i + 1
        expected_ratio = days_passed.fdiv(total_days)

        service.call

        expect(ChargeModels::Factory).to have_received(:new_instance).with(
          hash_including(period_ratio: expected_ratio)
        )
      end
    end
  end

  describe "edge cases" do
    context "when projected_amount is nil" do
      let(:charge_model_result) do
        instance_double(
          "ChargeModelResult",
          success?: true,
          error: nil,
          projected_amount: nil,
          projected_units: BigDecimal(10),
          unit_amount: nil
        )
      end

      it "returns 0 for amount cents" do
        result = service.call

        expect(result).to be_success
        expect(result.projected_amount_cents).to eq(0)
        expect(result.projected_pricing_unit_amount_cents).to eq(nil)
      end
    end

    context "when currency has different exponent" do
      let(:currency) do
        instance_double(
          "Currency",
          exponent: 3,
          subunit_to_unit: 1000
        )
      end

      it "rounds and converts correctly" do
        result = service.call

        expect(result).to be_success
        expect(result.projected_amount_cents).to eq(100500) # 100.50 * 1000
      end
    end
  end
end
