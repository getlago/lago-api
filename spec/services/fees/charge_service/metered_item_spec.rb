# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::MeteredItem do
  subject(:metered_item) { described_class.from_charge(charge:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
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

  describe ".from_charge" do
    it "builds a metered item backed by a charge source" do
      expect(metered_item.charge).to eq(charge)
      expect(metered_item.boundaries).to eq(boundaries)
      expect(metered_item.billable_metric).to eq(billable_metric)
    end
  end

  describe "delegations" do
    it "exposes charge source behavior" do
      expect(metered_item.organization_id).to eq(charge.organization_id)
      expect(metered_item.currency).to eq(charge.plan.amount.currency)
      expect(metered_item.properties).to eq(charge.properties)
      expect(metered_item.pricing_structure).to be_a(ChargeModels::PricingStructure)
      expect(metered_item).to have_attributes(
        charge_filter: nil,
        pay_in_advance?: false,
        prorated?: false,
        invoiceable?: true,
        applied_pricing_unit: nil
      )
    end
  end

  describe "#with_charge_filter" do
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "30"}) }

    it "returns a new metered item with the selected charge filter" do
      filtered_item = metered_item.with_charge_filter(charge_filter)

      expect(filtered_item).not_to eq(metered_item)
      expect(filtered_item.charge).to eq(charge)
      expect(filtered_item.charge_filter).to eq(charge_filter)
      expect(filtered_item.properties).to eq(charge_filter.properties)
    end
  end

  describe "#filtered_for_charge_boundaries" do
    it "returns fee properties without fixed charge boundaries" do
      expect(metered_item.filtered_for_charge_boundaries).to include(
        "charges_from_datetime" => Time.zone.parse("2022-03-01"),
        "charges_to_datetime" => Time.zone.parse("2022-03-31").end_of_day,
        "charges_duration" => 31,
        "fixed_charges_from_datetime" => nil,
        "fixed_charges_to_datetime" => nil,
        "fixed_charges_duration" => nil
      )
    end
  end
end
