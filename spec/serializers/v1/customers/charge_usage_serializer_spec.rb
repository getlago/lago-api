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

  let(:pricing_unit_usage) { nil }

  let(:usage) do
    [
      OpenStruct.new(
        charge_id: charge.id,
        subscription: subscription,
        billable_metric: billable_metric,
        charge: charge,
        units: "10",
        total_aggregated_units: "10",
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
    expect(result["charges"].first).to include(
      "units" => "10.0",
      "events_count" => 12,
      "amount_cents" => 100,
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
          "pricing_unit_details" => nil,
          "events_count" => 12,
          "units" => "10.0",
          "total_aggregated_units" => "10.0",
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
      expect(result["charges"].first).to include(
        "units" => "10.0",
        "total_aggregated_units" => "10.0",
        "events_count" => 12,
        "amount_cents" => 100,
        "pricing_unit_details" => {
          "amount_cents" => 200,
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
            "pricing_unit_details" => {
              "amount_cents" => 200,
              "short_name" => "CR",
              "conversion_rate" => "0.5"
            },
            "events_count" => 12,
            "units" => "10.0",
            "total_aggregated_units" => "10.0",
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

    it "returns filters array with projected values" do
      expect(result["charges"].first["filters"].first).to include(
        "units" => "30.0",
        "amount_cents" => 300,
        "events_count" => 36,
        "invoice_display_name" => charge_filter.invoice_display_name,
        "values" => {}
      )

      expect(result["charges"].first["grouped_usage"].first["filters"].first).to include(
        "units" => "30.0",
        "amount_cents" => 300,
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
        expect(result["charges"].first["filters"].first).to include(
          "units" => "30.0",
          "amount_cents" => 300,
          "pricing_unit_details" => {
            "amount_cents" => 600,
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
end
