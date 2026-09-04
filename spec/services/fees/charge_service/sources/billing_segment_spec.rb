# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Sources::BillingSegment do
  subject(:source) { described_class.new(billing_segment:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) do
    build(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "amount", recurring: true)
  end
  let(:product) { build(:product, organization:, billable_metric:) }
  let(:rate_card) { build(:rate_card, organization:, product:, currency: "USD", proration: true) }
  let(:contract_rate_card) { build(:contract_rate_card, organization:, rate_card:) }
  let(:rate_properties) { {"amount" => "30"} }
  let(:segment_rate_properties) do
    {"amount" => "20", "free_units_per_events" => "2", "free_units_per_total_aggregation" => "3"}
  end
  let(:rate_card_rate) do
    build(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties:)
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
      rate_properties: segment_rate_properties,
      proration_ratio: 0.5,
      billing_at: Time.zone.parse("2026-10-01"),
      cycle_started_at: Time.zone.parse("2026-09-01"),
      started_at: Time.zone.parse("2026-09-01"),
      ended_at: Time.zone.parse("2026-09-30").end_of_day
    )
  end

  describe "validations" do
    it "validates source inputs" do
      expect { described_class.new(billing_segment: nil) }
        .to raise_error(ArgumentError, "billing_segment must be a BillingSegment")
    end
  end

  describe "#properties" do
    it "uses the stored billing segment rate properties" do
      expect(source.properties).to eq(segment_rate_properties)
    end
  end

  describe "#pricing_structure" do
    it "uses the billing segment rate and stored properties" do
      expect(source.pricing_structure).to have_attributes(
        charge_model: "standard",
        properties: source.properties,
        prorated: true,
        accepts_target_wallet: false,
        currency: Money::Currency.new("USD")
      )
    end
  end

  describe "#aggregation_options" do
    it "returns aggregation options from stored properties" do
      expect(source.aggregation_options(current_usage: false)).to eq(
        free_units_per_events: 2,
        free_units_per_total_aggregation: 3.to_d,
        is_current_usage: false,
        is_pay_in_advance: false
      )
    end
  end

  describe "#period_ratio" do
    it "returns the persisted proration ratio" do
      expect(source.period_ratio).to eq(0.5)
    end
  end
end
