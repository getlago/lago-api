# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::ChargeUsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: "charges") }

  let(:charge) { create(:standard_charge) }
  let(:billable_metric) { charge.billable_metric }
  let(:pricing_unit_usage) { nil }

  let(:usage) do
    [
      OpenStruct.new(
        charge_id: charge.id,
        billable_metric:,
        charge:,
        units: 10,
        events_count: 12,
        amount_cents: 100,
        amount_currency: "EUR",
        invoice_display_name: charge.invoice_display_name,
        lago_id: billable_metric.id,
        name: billable_metric.name,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        grouped_by: {"card_type" => "visa"},
        pricing_unit_usage:
      ),
      OpenStruct.new(
        charge_id: charge.id,
        billable_metric:,
        charge:,
        units: 10,
        events_count: 12,
        amount_cents: 100,
        amount_currency: "EUR",
        invoice_display_name: charge.invoice_display_name,
        lago_id: billable_metric.id,
        name: billable_metric.name,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        grouped_by: {"card_type" => "mastercard"},
        pricing_unit_usage:
      )
    ]
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the fee" do
    expect(result["charges"].first).to include(
      "units" => "20.0",
      "events_count" => 24,
      "amount_cents" => 200,
      "pricing_unit_usage" => nil,
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
          "pricing_unit_usage" => nil,
          "events_count" => 12,
          "units" => "10.0",
          "grouped_by" => {"card_type" => "visa"},
          "filters" => []
        },
        {
          "amount_cents" => 100,
          "pricing_unit_usage" => nil,
          "events_count" => 12,
          "units" => "10.0",
          "grouped_by" => {"card_type" => "mastercard"},
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
        "units" => "20.0",
        "events_count" => 24,
        "amount_cents" => 200,
        "pricing_unit_usage" => {
          "amount_cents" => 400,
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
            "pricing_unit_usage" => {
              "amount_cents" => 200,
              "short_name" => "CR",
              "conversion_rate" => "0.5"
            },
            "events_count" => 12,
            "units" => "10.0",
            "grouped_by" => {"card_type" => "visa"},
            "filters" => []
          },
          {
            "amount_cents" => 100,
            "pricing_unit_usage" => {
              "amount_cents" => 200,
              "short_name" => "CR",
              "conversion_rate" => "0.5"
            },
            "events_count" => 12,
            "units" => "10.0",
            "grouped_by" => {"card_type" => "mastercard"},
            "filters" => []
          }
        ]
      )
    end
  end

  describe "#filters" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:) }
    let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: nil) }

    let(:usage) do
      Array.new(3) do
        OpenStruct.new(
          charge_id: charge.id,
          billable_metric:,
          charge:,
          units: "10.0",
          events_count: 12,
          amount_cents: 100,
          amount_currency: "EUR",
          invoice_display_name: charge.invoice_display_name,
          lago_id: billable_metric.id,
          name: billable_metric.name,
          code: billable_metric.code,
          aggregation_type: billable_metric.aggregation_type,
          grouped_by: {"card_type" => "visa"},
          charge_filter:,
          pricing_unit_usage:
        )
      end
    end

    it "returns filters array" do
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
          "pricing_unit_usage" => {
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
          "pricing_unit_usage" => {
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
