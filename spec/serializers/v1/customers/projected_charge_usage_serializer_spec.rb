# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::ProjectedChargeUsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: "charges", projections:) }

  let(:charge) { create(:standard_charge) }
  let(:billable_metric) { charge.billable_metric }
  let(:subscription) { create(:subscription, plan: charge.plan) }
  let(:result) { JSON.parse(serializer.to_json) }
  let(:pricing_unit_usage) { nil }
  let(:presentation_breakdowns) { [] }

  let(:projections) { UsageProjections.new(usage.zip(fee_projections).to_h.compare_by_identity) }

  let(:usage) do
    [
      build(
        :charge_fee,
        charge:,
        subscription:,
        units: "10",
        events_count: 12,
        amount_cents: 100,
        amount_currency: "EUR",
        grouped_by: {"card_type" => "visa"},
        charge_filter: nil,
        pricing_unit_usage:,
        presentation_breakdowns:
      )
    ]
  end
  let(:fee_projections) { [projection(units: 20, amount_cents: 200, pricing_unit_amount_cents:)] }
  let(:pricing_unit_amount_cents) { nil }

  def projection(units:, amount_cents:, pricing_unit_amount_cents: nil, presentation_breakdowns: [])
    UsageProjection.new(units: BigDecimal(units.to_s), amount_cents:, pricing_unit_amount_cents:, presentation_breakdowns:)
  end

  it "serializes the projected fee" do
    expect(result["charges"].first).to include(
      "units" => "10.0",
      "projected_units" => "20.0",
      "events_count" => 12,
      "amount_cents" => 100,
      "projected_amount_cents" => 200,
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
      "presentation_breakdowns" => [],
      "projected_presentation_breakdowns" => [],
      "grouped_usage" => [
        {
          "amount_cents" => 100,
          "projected_amount_cents" => 200,
          "projected_presentation_breakdowns" => [],
          "pricing_unit_details" => nil,
          "events_count" => 12,
          "units" => "10.0",
          "projected_units" => "20.0",
          "grouped_by" => {"card_type" => "visa"},
          "filters" => [],
          "presentation_breakdowns" => []
        }
      ]
    )
  end

  context "with presentation breakdowns" do
    let(:presentation_breakdowns) do
      [
        build(:presentation_breakdown, presentation_by: {"card_type" => "visa"}, units: "7"),
        build(:presentation_breakdown, presentation_by: {"country" => "br"}, units: "3")
      ]
    end
    let(:fee_projections) do
      [
        projection(
          units: 20,
          amount_cents: 200,
          presentation_breakdowns: [
            build(:presentation_breakdown, presentation_by: {"card_type" => "visa"}, units: "14"),
            build(:presentation_breakdown, presentation_by: {"country" => "br"}, units: "6")
          ]
        )
      ]
    end

    it "serializes the projected breakdowns on the grouped usage only" do
      charge_result = result["charges"].first

      expect(charge_result["presentation_breakdowns"]).to eq([])
      expect(charge_result["projected_presentation_breakdowns"]).to eq([])
      expect(charge_result["grouped_usage"].first["projected_presentation_breakdowns"]).to eq(
        [
          {"presentation_by" => {"card_type" => "visa"}, "units" => "14.0"},
          {"presentation_by" => {"country" => "br"}, "units" => "6.0"}
        ]
      )
    end
  end

  context "with pricing units" do
    let(:pricing_unit_usage) { PricingUnitUsage.new(amount_cents: 200, conversion_rate: 0.5, short_name: "CR") }
    let(:pricing_unit_amount_cents) { 400 }

    it "serializes the projected pricing unit amount" do
      expected_details = {
        "amount_cents" => 200,
        "projected_amount_cents" => 400,
        "short_name" => "CR",
        "conversion_rate" => "0.5"
      }

      expect(result["charges"].first["pricing_unit_details"]).to eq(expected_details)
      expect(result["charges"].first["grouped_usage"].first["pricing_unit_details"]).to eq(expected_details)
    end
  end

  context "with charge filters" do
    let(:charge_filter_1) { create(:charge_filter, charge:, invoice_display_name: "Filter 1") }
    let(:charge_filter_2) { create(:charge_filter, charge:, invoice_display_name: "Filter 2") }
    let(:usage) do
      [
        build(:charge_fee, charge:, subscription:, units: "5.0", events_count: 8, amount_cents: 50, amount_currency: "EUR", grouped_by: {}, charge_filter: charge_filter_1),
        build(:charge_fee, charge:, subscription:, units: "7.0", events_count: 10, amount_cents: 70, amount_currency: "EUR", grouped_by: {}, charge_filter: charge_filter_2),
        build(:charge_fee, charge:, subscription:, units: "1.0", events_count: 1, amount_cents: 10, amount_currency: "EUR", grouped_by: {}, charge_filter: nil)
      ]
    end
    let(:fee_projections) do
      [
        projection(units: 10, amount_cents: 100),
        projection(units: 14, amount_cents: 140),
        projection(units: 2, amount_cents: 20)
      ]
    end

    it "serializes each filter projection and sums them, default filter included, on the charge" do
      charge_result = result["charges"].first

      expect(charge_result).to include("projected_units" => "26.0", "projected_amount_cents" => 260)
      expect(charge_result["filters"].map { |f| f.slice("invoice_display_name", "projected_units", "projected_amount_cents") }).to match_array(
        [
          {"invoice_display_name" => "Filter 1", "projected_units" => "10.0", "projected_amount_cents" => 100},
          {"invoice_display_name" => "Filter 2", "projected_units" => "14.0", "projected_amount_cents" => 140},
          {"invoice_display_name" => nil, "projected_units" => "2.0", "projected_amount_cents" => 20}
        ]
      )
    end
  end

  context "with groups and filters" do
    let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Mixed Filter") }
    let(:usage) do
      [
        build(:charge_fee, charge:, subscription:, units: "2.0", events_count: 3, amount_cents: 20, amount_currency: "EUR", grouped_by: {"datacenter" => "dc1"}, charge_filter:),
        build(:charge_fee, charge:, subscription:, units: "3.0", events_count: 4, amount_cents: 30, amount_currency: "EUR", grouped_by: {"datacenter" => "dc2"}, charge_filter:)
      ]
    end
    let(:fee_projections) { [projection(units: 4, amount_cents: 40), projection(units: 6, amount_cents: 60)] }

    it "sums the projections at the filter level and keeps them apart per group" do
      charge_result = result["charges"].first

      expect(charge_result["filters"].sole).to include("projected_units" => "10.0", "projected_amount_cents" => 100)
      expect(charge_result["grouped_usage"].map { |g| g.slice("grouped_by", "projected_units", "projected_amount_cents") }).to eq(
        [
          {"grouped_by" => {"datacenter" => "dc1"}, "projected_units" => "4.0", "projected_amount_cents" => 40},
          {"grouped_by" => {"datacenter" => "dc2"}, "projected_units" => "6.0", "projected_amount_cents" => 60}
        ]
      )
    end
  end

  context "with several charges" do
    let(:charge_2) { create(:standard_charge) }
    let(:usage) do
      [
        build(:charge_fee, charge:, subscription:, units: "10.0", events_count: 15, amount_cents: 100, amount_currency: "EUR", grouped_by: {}, charge_filter: nil),
        build(:charge_fee, charge: charge_2, subscription:, units: "20.0", events_count: 25, amount_cents: 200, amount_currency: "EUR", grouped_by: {}, charge_filter: nil)
      ]
    end
    let(:fee_projections) { [projection(units: 20, amount_cents: 200), projection(units: 40, amount_cents: 400)] }

    it "serializes each charge with its own projection" do
      expect(result["charges"].map { |c| [c["charge"]["lago_id"], c["projected_units"], c["projected_amount_cents"]] }).to eq(
        [
          [charge.id, "20.0", 200],
          [charge_2.id, "40.0", 400]
        ]
      )
    end
  end
end
