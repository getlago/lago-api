# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::ChargeUsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: "charges") }

  let(:charge) { create(:standard_charge) }
  let(:result) { JSON.parse(serializer.to_json) }
  let(:billable_metric) { charge.billable_metric }
  let(:subscription) { create(:subscription, plan: charge.plan) }
  let(:from_datetime) { Date.new(2025, 7, 1) }
  let(:to_datetime) { Date.new(2025, 7, 10) } # 10 day period for clean ratios
  let(:fixed_date) { Date.new(2025, 7, 5) } # 5 days passed, ratio = 0.5

  let(:total_days) { (to_datetime - from_datetime).to_i + 1 }
  let(:charges_duration) { total_days }
  let(:days_passed) { (fixed_date - from_datetime).to_i + 1 }
  let(:ratio) { days_passed.to_f / charges_duration }

  let(:is_recurring) { false }
  let(:expected_projected_units) do
    "0.0"
    # if is_recurring
    #   BigDecimal("10")
    # else
    #   (ratio > 0) ? (BigDecimal("10") / BigDecimal(ratio.to_s)).round(1) : BigDecimal("0")
    # end
  end
  let(:expected_projected_amount_cents) do
    0
    # if is_recurring
    #   100
    # else
    #   (ratio > 0) ? (BigDecimal("100") / BigDecimal(ratio.to_s)).round.to_i : 0
    # end
  end
  let(:expected_pricing_unit_projected_amount_cents) do
    0
    # if is_recurring
    #   200
    # else
    #   (ratio > 0) ? (BigDecimal("200") / BigDecimal(ratio.to_s)).round.to_i : 0
    # end
  end
  let(:greater_expected_pricing_unit_projected_amount_cents) do
    0
    # if is_recurring
    #   600
    # else
    #   (ratio > 0) ? (BigDecimal("600") / BigDecimal(ratio.to_s)).round.to_i : 0
    # end
  end
  let(:pricing_unit_usage) { nil }

  let(:usage) do
    [
      OpenStruct.new(
        charge_id: charge.id,
        subscription: subscription,
        billable_metric: billable_metric,
        charge: charge,
        units: "10",
        events_count: 12,
        amount_cents: 100,
        amount_currency: "EUR",
        properties: {
          "from_datetime" => from_datetime.to_s,
          "to_datetime" => to_datetime.to_s,
          "charges_duration" => charges_duration
        },
        invoice_display_name: charge.invoice_display_name,
        lago_id: billable_metric.id,
        name: billable_metric.name,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        grouped_by: {"card_type" => "visa"},
        charge_filter: nil,
        pricing_unit_usage:
      )
    ]
  end

  before do
    allow(Date).to receive(:current).and_return(fixed_date)
    allow(Time).to receive(:current).and_return(fixed_date.to_time)
  end

  it "serializes the fee" do
    projection_result = instance_double(
      "ProjectionResult",
      projected_units: expected_projected_units,
      projected_amount_cents: expected_projected_amount_cents,
      projected_pricing_unit_amount_cents: expected_pricing_unit_projected_amount_cents
    )

    allow(::Fees::ProjectionService).to receive(:call).and_return(
      instance_double("ServiceResult", raise_if_error!: projection_result)
    )

    expect(result["charges"].first).to include(
      "units" => "10.0",
      "projected_units" => expected_projected_units.to_s,
      "events_count" => 12,
      "amount_cents" => 100,
      "projected_amount_cents" => expected_projected_amount_cents,
      "pricing_unit_details" => nil,
      "amount_currency" => "EUR",
      "charge" => {
        "lago_id" => charge.id,
        "charge_model" => charge.charge_model,
        "invoice_display_name" => charge.invoice_display_name
      },
      "billable_metric" => {
        "lago_id" => billable_metric.id,
        "name" => billable_metric.name,
        "code" => billable_metric.code,
        "aggregation_type" => billable_metric.aggregation_type
      },
      "filters" => [],
      "grouped_usage" => [
        {
          "amount_cents" => 100,
          "projected_amount_cents" => expected_projected_amount_cents,
          "pricing_unit_details" => nil,
          "events_count" => 12,
          "units" => "10.0",
          "projected_units" => expected_projected_units.to_s,
          "grouped_by" => {"card_type" => "visa"},
          "filters" => []
        }
      ]
    )
  end

  context "when charge configured to use pricing units" do
    let(:pricing_unit_usage) do
      PricingUnitUsage.new(amount_cents: 200, conversion_rate: 0.5, short_name: "CR")
    end

    it "serializes the fee" do
      projection_result = instance_double(
        "ProjectionResult",
        projected_units: expected_projected_units,
        projected_amount_cents: expected_projected_amount_cents,
        projected_pricing_unit_amount_cents: expected_pricing_unit_projected_amount_cents
      )

      allow(::Fees::ProjectionService).to receive(:call).and_return(
        instance_double("ServiceResult", raise_if_error!: projection_result)
      )

      expect(result["charges"].first).to include(
        "units" => "10.0",
        "projected_units" => expected_projected_units.to_s,
        "events_count" => 12,
        "amount_cents" => 100,
        "projected_amount_cents" => expected_projected_amount_cents,
        "pricing_unit_details" => {
          "amount_cents" => 200,
          "projected_amount_cents" => expected_pricing_unit_projected_amount_cents,
          "short_name" => "CR",
          "conversion_rate" => "0.5"
        },
        "amount_currency" => "EUR",
        "charge" => {
          "lago_id" => charge.id,
          "charge_model" => charge.charge_model,
          "invoice_display_name" => charge.invoice_display_name
        },
        "billable_metric" => {
          "lago_id" => billable_metric.id,
          "name" => billable_metric.name,
          "code" => billable_metric.code,
          "aggregation_type" => billable_metric.aggregation_type
        },
        "filters" => [],
        "grouped_usage" => [
          {
            "amount_cents" => 100,
            "projected_amount_cents" => expected_projected_amount_cents,
            "pricing_unit_details" => {
              "amount_cents" => 200,
              "projected_amount_cents" => expected_pricing_unit_projected_amount_cents,
              "short_name" => "CR",
              "conversion_rate" => "0.5"
            },
            "events_count" => 12,
            "units" => "10.0",
            "projected_units" => expected_projected_units.to_s,
            "grouped_by" => {"card_type" => "visa"},
            "filters" => []
          }
        ]
      )
    end
  end

  describe "#filters" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: billable_metric) }
    let(:charge_filter) { create(:charge_filter, charge: charge, invoice_display_name: nil) }
    let(:usage) do
      Array.new(3) do
        OpenStruct.new(
          charge_id: charge.id,
          subscription: subscription,
          billable_metric: billable_metric,
          charge: charge,
          units: "10.0",
          events_count: 12,
          amount_cents: 100,
          amount_currency: "EUR",
          properties: {
            "from_datetime" => from_datetime.to_s,
            "to_datetime" => to_datetime.to_s,
            "charges_duration" => charges_duration
          },
          grouped_by: {"card_type" => "visa"},
          charge_filter:,
          charge_filter_id: charge_filter.id,
          pricing_unit_usage:
        )
      end
    end

    let(:expected_filter_projected_units) do
      "0.0"
      # if is_recurring
      #   BigDecimal("30")
      # else
      #   (ratio > 0) ? (BigDecimal("30") / BigDecimal(ratio.to_s)).round(2) : BigDecimal("0")
      # end
    end
    let(:expected_filter_projected_amount_cents) do
      0
      # if is_recurring
      #   300
      # else
      #   (ratio > 0) ? (300 / BigDecimal(ratio.to_s)).round.to_i : 0
      # end
    end

    it "returns filters array with projected values" do
      individual_projection_result = instance_double(
        "ProjectionResult",
        projected_units: "0.0",
        # projected_units: expected_filter_projected_units / 3,
        projected_amount_cents: 0,
        # projected_amount_cents: expected_filter_projected_amount_cents / 3,
        projected_pricing_unit_amount_cents: 0
        # projected_pricing_unit_amount_cents: greater_expected_pricing_unit_projected_amount_cents / 3
      )

      allow(::Fees::ProjectionService).to receive(:call).and_return(
        instance_double("ServiceResult", raise_if_error!: individual_projection_result)
      )

      expect(result["charges"].first["filters"].first).to include(
        "units" => "30.0",
        "projected_units" => expected_filter_projected_units.to_s,
        "amount_cents" => 300,
        "projected_amount_cents" => expected_filter_projected_amount_cents,
        "events_count" => 36,
        "invoice_display_name" => charge_filter.invoice_display_name,
        "values" => {}
      )

      expect(result["charges"].first["grouped_usage"].first["filters"].first).to include(
        "units" => "30.0",
        "projected_units" => expected_filter_projected_units.to_s,
        "amount_cents" => 300,
        "projected_amount_cents" => expected_filter_projected_amount_cents,
        "events_count" => 36,
        "invoice_display_name" => charge_filter.invoice_display_name,
        "values" => {}
      )
    end

    context "when charge configured to use pricing units" do
      let(:pricing_unit_usage) do
        PricingUnitUsage.new(amount_cents: 200, conversion_rate: 0.5, short_name: "CR")
      end

      it "returns filters array" do
        individual_projection_result = instance_double(
          "ProjectionResult",
          projected_units: "0.0",
          # projected_units: expected_filter_projected_units / 3,
          projected_amount_cents: 0,
          # projected_amount_cents: expected_filter_projected_amount_cents / 3,
          projected_pricing_unit_amount_cents: 0
          # projected_pricing_unit_amount_cents: greater_expected_pricing_unit_projected_amount_cents / 3
        )

        allow(::Fees::ProjectionService).to receive(:call).and_return(
          instance_double("ServiceResult", raise_if_error!: individual_projection_result)
        )

        expect(result["charges"].first["filters"].first).to include(
          "units" => "30.0",
          "amount_cents" => 300,
          "pricing_unit_details" => {
            "amount_cents" => 600,
            "projected_amount_cents" => greater_expected_pricing_unit_projected_amount_cents,
            "short_name" => "CR",
            "conversion_rate" => "0.5"
          },
          "events_count" => 36,
          "invoice_display_name" => charge_filter.invoice_display_name,
          "values" => {}
        )

        expect(result["charges"].first["grouped_usage"].first["filters"].first).to include(
          "units" => "30.0",
          "amount_cents" => 300,
          "pricing_unit_details" => {
            "amount_cents" => 600,
            "projected_amount_cents" => greater_expected_pricing_unit_projected_amount_cents,
            "short_name" => "CR",
            "conversion_rate" => "0.5"
          },
          "events_count" => 36,
          "invoice_display_name" => charge_filter.invoice_display_name,
          "values" => {}
        )
      end
    end
  end

  describe "recurring charges" do
    let(:is_recurring) { true }

    before do
      allow(charge.billable_metric).to receive(:recurring?).and_return(true)
    end

    it "does not project values for recurring charges" do
      projection_result = instance_double(
        "ProjectionResult",
        projected_units: "0.0",
        # projected_units: BigDecimal("10"),
        projected_amount_cents: 0,
        # projected_amount_cents: 100,
        projected_pricing_unit_amount_cents: 0
        # projected_pricing_unit_amount_cents: 200
      )

      allow(::Fees::ProjectionService).to receive(:call).and_return(
        instance_double("ServiceResult", raise_if_error!: projection_result)
      )

      expect(result["charges"].first).to include(
        "units" => "10.0",
        "projected_units" => "0.0",
        "projected_amount_cents" => 0
      )
    end
  end

  describe "past_usage root_name" do
    subject(:serializer) { described_class.new(usage, root_name: "past_usage") }

    it "sets projected values to zero for past_usage" do
      expect(result["past_usage"].first).to include(
        "units" => "10.0",
        "projected_units" => "0.0",
        "projected_amount_cents" => 0
      )
    end
  end
end
