# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Sources::Charge do
  subject(:source) { described_class.new(charge:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric:,
      properties: {amount: "20", free_units_per_events: "2", free_units_per_total_aggregation: "3"}
    )
  end
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: Time.zone.parse("2022-03-01"),
      to_datetime: Time.zone.parse("2022-03-31").end_of_day,
      charges_from_datetime: Time.zone.parse("2022-03-01"),
      charges_to_datetime: Time.zone.parse("2022-03-31").end_of_day,
      charges_duration: 31,
      timestamp: Time.zone.parse("2022-04-01")
    )
  end

  describe "fee identity" do
    it "exposes charge fee attributes individually" do
      expect(source).to have_attributes(fee_type: :charge, invoiceable: charge)
    end
  end

  describe "#with_filter" do
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "30"}) }

    it "returns a source with the selected filter" do
      filtered_source = source.with_filter(charge_filter)

      expect(filtered_source.charge).to eq(charge)
      expect(filtered_source.boundaries).to eq(boundaries)
      expect(filtered_source.charge_filter).to eq(charge_filter)
      expect(filtered_source.properties).to eq(charge_filter.properties)
      expect(filtered_source.selected_filter).to eq(charge_filter)
    end

    it "clears the selected filter" do
      filtered_source = source.with_filter(charge_filter)

      expect(filtered_source.with_filter(nil)).to have_attributes(selected_filter: nil, properties: charge.properties)
    end
  end

  describe "#properties" do
    it "uses explicit properties before filter and charge properties" do
      charge_filter = create(:charge_filter, charge:, properties: {amount: "30"})

      expect(source.properties).to eq(charge.properties)
      expect(source.with_filter(charge_filter).properties).to eq(charge_filter.properties)
      expect(source.with_filter(charge_filter, properties: {amount: "40"}).properties).to eq({amount: "40"})
    end
  end

  describe "#period_ratio" do
    around { |test| travel_to(Time.zone.parse("2022-03-16")) { test.run } }

    it "returns the elapsed charge period ratio" do
      expect(source.period_ratio).to eq(16.fdiv(31))
    end
  end

  describe "#pricing_group_keys" do
    it "returns charge pricing group keys" do
      charge.update!(properties: charge.properties.merge("pricing_group_keys" => ["region"]))

      expect(source.pricing_group_keys).to eq(["region"])
    end
  end
end
