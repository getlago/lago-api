# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ProjectionService do
  subject(:result) { described_class.call!(fee:, timezone:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, properties: {amount: "0.1"}) }
  let(:charge_filter) { nil }
  let(:timezone) { "UTC" }

  let(:from_datetime) { Time.zone.parse("2025-01-01T00:00:00") }
  let(:to_datetime) { Time.zone.parse("2025-01-10T23:59:59") }
  let(:current_time) { Time.zone.parse("2025-01-05T12:00:00") } # 5 of 10 days, ratio 0.5

  let(:units) { "10" }
  let(:amount_cents) { 100 }
  let(:precise_amount_cents) { BigDecimal(amount_cents) }
  let(:pricing_unit_usage) { nil }
  let(:currency) { "EUR" }

  let(:fee) do
    build(
      :charge_fee,
      organization:,
      charge:,
      charge_filter:,
      units:,
      amount_cents:,
      precise_amount_cents:,
      amount_currency: currency,
      pricing_unit_usage:,
      properties: {"from_datetime" => from_datetime.iso8601, "to_datetime" => to_datetime.iso8601}
    )
  end

  around { |example| travel_to(current_time) { example.run } }

  it "reprices the projected units with the charge properties" do
    expect(result.projection).to have_attributes(
      units: BigDecimal(20),
      amount_cents: 200,
      pricing_unit_amount_cents: nil,
      presentation_breakdowns: []
    )
  end

  context "with a graduated charge" do
    let(:charge) do
      create(
        :graduated_charge,
        billable_metric:,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 10, per_unit_amount: "0.1", flat_amount: "0"},
            {from_value: 11, to_value: nil, per_unit_amount: "0.05", flat_amount: "0"}
          ]
        }
      )
    end

    it "prices the projected units through the tiers" do
      expect(result.projection).to have_attributes(units: BigDecimal(20), amount_cents: 150)
    end
  end

  context "with a charge filter" do
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "1"}) }

    it "prices the projected units with the filter properties" do
      expect(result.projection).to have_attributes(units: BigDecimal(20), amount_cents: 2000)
    end
  end

  context "with a grouped charge" do
    let(:charge) { create(:standard_charge, billable_metric:, properties: {amount: "0.1", pricing_group_keys: ["region"]}) }

    it "projects the group of the fee" do
      expect(result.projection).to have_attributes(units: BigDecimal(20), amount_cents: 200)
    end
  end

  context "with a percentage charge" do
    let(:charge) { create(:percentage_charge, billable_metric:) }
    let(:precise_amount_cents) { BigDecimal("123.4") }

    it "scales the current amount" do
      expect(result.projection).to have_attributes(units: BigDecimal(20), amount_cents: 247)
    end
  end

  context "with pricing units" do
    let(:pricing_unit) { create(:pricing_unit, organization:) }
    let(:applied_pricing_unit) { create(:applied_pricing_unit, organization:, pricing_unit:, pricing_unitable: charge, conversion_rate: 0.5) }
    let(:pricing_unit_usage) do
      build(:pricing_unit_usage, organization:, pricing_unit:, amount_cents: 100, precise_amount_cents: BigDecimal("100.6"), conversion_rate: 0.5)
    end
    let(:amount_cents) { 50 }

    before { applied_pricing_unit }

    it "prices the projected units in pricing units and converts them to the fee currency" do
      expect(result.projection).to have_attributes(amount_cents: 100, pricing_unit_amount_cents: 200)
    end

    context "with a percentage charge" do
      let(:charge) { create(:percentage_charge, billable_metric:) }

      it "scales both amounts" do
        expect(result.projection).to have_attributes(amount_cents: 100, pricing_unit_amount_cents: 201)
      end
    end
  end

  context "with presentation breakdowns" do
    before do
      fee.presentation_breakdowns.build(organization:, presentation_by: {"department" => "engineering"}, units: 60.33642)
    end

    it "projects the breakdown units" do
      expect(result.projection.presentation_breakdowns).to match_array([
        have_attributes(presentation_by: {"department" => "engineering"}, units: 120.67)
      ])
    end
  end

  context "with a recurring billable metric" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

    before do
      fee.presentation_breakdowns.build(organization:, presentation_by: {"department" => "engineering"}, units: 60)
    end

    it "returns the current usage" do
      expect(result.projection).to have_attributes(
        units: BigDecimal(10),
        amount_cents: 100,
        presentation_breakdowns: [have_attributes(units: 60)]
      )
    end
  end

  context "when the period has not started" do
    let(:current_time) { from_datetime - 1.day }

    it "returns a zero projection" do
      expect(result.projection).to eq(UsageProjection.zero)
    end
  end

  context "when the period is over" do
    let(:current_time) { to_datetime + 1.hour }

    it "projects the current usage" do
      expect(result.projection).to have_attributes(units: BigDecimal(10), amount_cents: 100)
    end
  end

  context "with a customer timezone" do
    let(:timezone) { "America/New_York" }
    let(:from_datetime) { Time.zone.parse("2025-01-01T05:00:00") }
    let(:to_datetime) { Time.zone.parse("2025-02-01T04:59:59") }
    let(:current_time) { from_datetime + 10.days }

    it "computes the elapsed ratio in the customer timezone" do
      expect(result.projection.units).to eq((BigDecimal(10) / 11.fdiv(31).to_d).round(2))
    end
  end

  context "with a currency of a different exponent" do
    let(:currency) { "KWD" }
    let(:amount_cents) { 1000 }

    it "rounds the projected amount to the currency exponent" do
      expect(result.projection.amount_cents).to eq(2000)
    end
  end
end
