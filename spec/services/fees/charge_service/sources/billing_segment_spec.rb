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

  describe "#charge_id" do
    it "returns nil for a catalog product without a legacy charge" do
      expect(source.charge_id).to be_nil
    end

    context "with a legacy charge" do
      let(:charge) { build_stubbed(:standard_charge) }
      let(:product) { build(:product, organization:, billable_metric:, charge:) }

      it "returns the linked charge ID" do
        expect(source.charge_id).to eq(charge.id)
      end
    end
  end

  describe "fee identity" do
    it "exposes product fee attributes individually" do
      expect(source).to have_attributes(
        fee_type: :product, invoiceable: product, contract: billing_segment.contract,
        rate_card_rate:, rate_override: nil
      )
    end
  end

  describe "#matching_and_ignored_filters" do
    it "returns equal results using the shared filter result type" do
      result = source.matching_and_ignored_filters

      expect(result).to be_a(ChargeFilters::MatchingAndIgnoredService::Result)
      expect(result).to have_attributes(matching_filters: {}, ignored_filters: [])
      expect(source.matching_and_ignored_filters).to eq(result)
    end

    context "with a selected product filter" do
      let(:product_filter) { build(:product_filter, organization:, product:) }

      before do
        rate_card.product_filter = product_filter
        allow(product_filter).to receive(:to_h).and_return({"region" => ["us"]})
      end

      it "matches the selected filter without ignoring other filters" do
        expect(source.matching_and_ignored_filters).to have_attributes(
          matching_filters: {"region" => ["us"]}, ignored_filters: []
        )
      end

      it "supports an explicit default bucket without changing segment properties" do
        filtered_source = source.with_filter(nil)

        expect(source.selected_filter).to eq(product_filter)
        expect(filtered_source).to have_attributes(selected_filter: nil, properties: segment_rate_properties)
        expect(filtered_source.matching_and_ignored_filters).to have_attributes(matching_filters: {}, ignored_filters: [])
      end

      it "allows selecting a filter from the default bucket" do
        filtered_source = source.with_filter(nil).with_filter(product_filter)

        expect(filtered_source).to have_attributes(selected_filter: product_filter, billing_segment:)
        expect(filtered_source.matching_and_ignored_filters).to have_attributes(
          matching_filters: {"region" => ["us"]}, ignored_filters: []
        )
      end
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

  describe "#period_ratio" do
    it "returns the persisted proration ratio" do
      expect(source.period_ratio).to eq(0.5)
    end
  end

  describe "#pricing_group_keys" do
    let(:segment_rate_properties) { {"pricing_group_keys" => ["region"]} }

    it "returns the pricing group keys from the stored properties" do
      expect(source.pricing_group_keys).to eq(["region"])
    end

    context "when the rate card accepts target wallet grouping" do
      let(:rate_card) { build(:rate_card, organization:, product:, currency: "USD", wallet_targetable: true) }

      it "adds the target wallet code to the pricing group keys" do
        expect(source.pricing_group_keys).to eq(["region", ::Charge::EVENT_TARGET_WALLET_CODE])
      end
    end
  end
end
