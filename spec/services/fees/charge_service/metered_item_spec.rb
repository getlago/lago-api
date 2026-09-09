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
      expect(metered_item).to have_attributes(fee_type: :charge, invoiceable: charge)
    end
  end

  describe ".from_billing_segment" do
    let(:billable_metric) do
      build(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "amount", recurring: true)
    end
    let(:product) { build(:product, organization:, billable_metric:) }
    let(:rate_card) { build(:rate_card, organization:, product:, currency: "USD", proration: true) }
    let(:contract_rate_card) { build(:contract_rate_card, organization:, rate_card:) }
    let(:rate_card_rate) do
      build(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "42"})
    end
    let(:billing_segment) do
      build(
        :billing_segment,
        organization:,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        rate_card_rate:,
        currency: "USD",
        rate_properties: {"amount" => "24"},
        proration_ratio: 0.5,
        billing_at: Time.zone.parse("2026-10-01"),
        cycle_started_at: Time.zone.parse("2026-09-01"),
        started_at: Time.zone.parse("2026-09-01"),
        ended_at: Time.zone.parse("2026-09-30").end_of_day
      )
    end

    it "builds a metered item backed by a billing segment source" do
      metered_item = described_class.from_billing_segment(billing_segment)

      expect(metered_item.billing_segment).to eq(billing_segment)
      expect(metered_item.charge_id).to be_nil
      expect(metered_item).not_to be_dynamic
      expect(metered_item.billable_metric).to eq(billable_metric)
      expect(metered_item.properties).to eq("amount" => "24")
      expect(metered_item.period_ratio).to eq(0.5)
      expect(metered_item.currency).to eq(Money::Currency.new("USD"))
      expect(metered_item.boundaries).to have_attributes(
        charges_from_datetime: billing_segment.started_at,
        charges_to_datetime: billing_segment.ended_at,
        charges_duration: 30,
        timestamp: billing_segment.billing_at
      )
    end

    it "defaults absent attributes without masking segment references" do
      expect(described_class.from_billing_segment(billing_segment)).to have_attributes(
        charge_filter: nil, product_filter: nil, contract: billing_segment.contract,
        rate_card_rate:, rate_override: nil, fee_type: :product, invoiceable: product
      )
    end

    it "reflects the segment rate model and prefers the override model" do
      metered_item = described_class.from_billing_segment(billing_segment)
      rate_card_rate.rate_model = "dynamic"
      expect(metered_item).to be_dynamic

      billing_segment.rate_override = build(:rate_override, organization:, rate_model: "standard")
      expect(metered_item).not_to be_dynamic
      expect(metered_item.rate_override).to eq(billing_segment.rate_override)
    end

    it "uses the selected product filter and supports an explicit default bucket" do
      product_filter = build(:product_filter, organization:, product:, id: SecureRandom.uuid)
      rate_card.product_filter = product_filter
      metered_item = described_class.from_billing_segment(billing_segment)

      expect(metered_item).to have_attributes(product_filter:, selected_filter: product_filter, filter_id: product_filter.id)
      expect(metered_item.with_filter(nil)).to have_attributes(product_filter: nil, selected_filter: nil, filter_id: nil)
    end

    it "builds aggregation options from the stored segment properties" do
      billing_segment.rate_properties = {
        "free_units_per_events" => "2", "free_units_per_total_aggregation" => "3"
      }
      rate_card.billing_timing = :advance

      expect(described_class.from_billing_segment(billing_segment).aggregation_options(current_usage: false)).to eq(
        free_units_per_events: 2,
        free_units_per_total_aggregation: 3.to_d,
        is_current_usage: false,
        is_pay_in_advance: true
      )
    end
  end

  describe "delegations" do
    it "defaults attributes that do not apply to a charge" do
      expect(metered_item).to have_attributes(
        billing_segment: nil, product_filter: nil, contract: nil, rate_card_rate: nil, rate_override: nil
      )
    end

    it "exposes charge source behavior" do
      expect(metered_item.organization_id).to eq(charge.organization_id)
      expect(metered_item.currency).to eq(charge.plan.amount.currency)
      expect(metered_item.properties).to eq(charge.properties)
      expect(metered_item.pricing_structure).to be_a(ChargeModels::PricingStructure)
      expect(metered_item).to have_attributes(
        charge_id: charge.id,
        dynamic?: false,
        charge_filter: nil,
        pay_in_advance?: false,
        prorated?: false,
        invoiceable?: true,
        applied_pricing_unit: nil
      )
    end
  end

  describe "#dynamic?" do
    it "reflects the backing charge's pricing model" do
      charge.charge_model = "dynamic"

      expect(metered_item).to be_dynamic
    end
  end

  describe "#aggregation_options" do
    it "uses charge properties and current usage flags" do
      charge.properties = {"free_units_per_events" => "2", "free_units_per_total_aggregation" => "3"}

      expect(metered_item.aggregation_options(current_usage: true)).to eq(
        free_units_per_events: 2,
        free_units_per_total_aggregation: 3.to_d,
        is_current_usage: true,
        is_pay_in_advance: false
      )
    end

    it "defaults missing free units to zero" do
      expect(metered_item.aggregation_options(current_usage: false)).to eq(
        free_units_per_events: 0,
        free_units_per_total_aggregation: 0.to_d,
        is_current_usage: false,
        is_pay_in_advance: false
      )
    end
  end

  describe "#with_filter" do
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "30"}) }

    it "returns a new metered item with the selected charge filter" do
      filtered_item = metered_item.with_filter(charge_filter)

      expect(filtered_item).not_to eq(metered_item)
      expect(filtered_item.charge).to eq(charge)
      expect(filtered_item.charge_filter).to eq(charge_filter)
      expect(filtered_item.properties).to eq(charge_filter.properties)
      expect(filtered_item.filter_id).to eq(charge_filter.id)
      expect(metered_item.filter_id).to be_nil
    end

    it "forwards property overrides" do
      filtered_item = metered_item.with_filter(charge_filter, properties: {"amount" => "40"})

      expect(filtered_item).to have_attributes(charge_filter:, properties: {"amount" => "40"})
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
