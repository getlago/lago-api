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
    subject(:service_result) { source.matching_and_ignored_filters }

    let(:source) { described_class.new(billing_segment:, product_filter:) }
    let(:product_filter) { nil }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, rate_card:) }

    it "memoizes the result per source without sharing it with a new filter source" do
      allow(Events::BillingPeriodFilters::MatchingAndIgnoredService).to receive(:call).and_return(BaseResult.new)

      result = source.matching_and_ignored_filters

      expect(source.matching_and_ignored_filters).to equal(result)
      expect(Events::BillingPeriodFilters::MatchingAndIgnoredService).to have_received(:call).once

      source.with_filter(nil).matching_and_ignored_filters

      expect(Events::BillingPeriodFilters::MatchingAndIgnoredService).to have_received(:call).twice
    end

    context "when product_filter is nil and the product has no filters" do
      it "returns empty matching and ignored filters" do
        expect(service_result).to be_a(Events::BillingPeriodFilters::MatchingAndIgnoredService::Result)
        expect(service_result).to have_attributes(matching_filters: {}, ignored_filters: [])
      end
    end

    context "when the product has filters" do
      let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }
      let(:size) { create(:billable_metric_filter, organization:, billable_metric:, key: "size", values: %w[512 1024]) }
      let(:us_filter) { create(:product_filter, organization:, product:) }
      let(:specific_filter) { create(:product_filter, organization:, product:) }
      let(:all_regions_filter) { create(:product_filter, organization:, product:) }

      before do
        create(:product_filter_value, organization:, product_filter: us_filter, billable_metric_filter: region, value: "us")
        create(:product_filter_value, organization:, product_filter: specific_filter, billable_metric_filter: region, value: "us")
        create(:product_filter_value, organization:, product_filter: specific_filter, billable_metric_filter: size, value: "512")
        create(:product_filter_value, organization:, product_filter: all_regions_filter, billable_metric_filter: region, value: nil)
      end

      context "when product_filter is nil" do
        it "excludes all product filters with nil values expanded to configured values" do
          expect(service_result.matching_filters).to eq({})
          expect(service_result.ignored_filters).to match_array([
            {"region" => ["us"]},
            {"region" => ["us"], "size" => ["512"]},
            {"region" => %w[us eu]}
          ])
        end

        it "uses an empty filter only for matching without persisting or selecting it" do
          source

          expect { service_result }.not_to change(ProductFilter, :count)
          expect(source).to have_attributes(product_filter: nil, selected_filter: nil)
          expect(service_result).to eq(
            source.with_filter(ProductFilter.new(organization:, product:)).matching_and_ignored_filters
          )
        end
      end

      context "with an explicit filter value" do
        let(:product_filter) { us_filter }

        it "excludes the more specific filter and the remaining configured region" do
          expect(service_result.matching_filters).to eq("region" => ["us"])
          expect(service_result.ignored_filters).to match_array([
            {"region" => ["us"], "size" => ["512"]},
            {"region" => ["eu"]}
          ])
        end

        it "uses default-bucket exclusions when the selected filter is cleared" do
          default_source = source.with_filter(nil)
          result = default_source.matching_and_ignored_filters

          expect(default_source.properties).to eq(segment_rate_properties)
          expect(default_source).to have_attributes(product_filter: nil, selected_filter: nil)
          expect(result.matching_filters).to eq({})
          expect(result.ignored_filters).to match_array([
            {"region" => ["us"]},
            {"region" => ["us"], "size" => ["512"]},
            {"region" => %w[us eu]}
          ])
        end
      end

      context "with the most specific product filter" do
        let(:product_filter) { specific_filter }

        it "matches both keys without excluding broader filters" do
          expect(service_result.matching_filters).to eq("region" => ["us"], "size" => ["512"])
          expect(service_result.ignored_filters).to eq([])
        end
      end

      context "with a nil product filter value" do
        let(:product_filter) { all_regions_filter }

        it "matches all configured values rather than nil or arbitrary values carrying the key" do
          expect(product_filter.to_h).to eq("region" => [nil])
          expect(service_result.matching_filters).to eq("region" => %w[us eu])
          expect(service_result.ignored_filters).to match_array([
            {"region" => ["us"]},
            {"region" => ["us"], "size" => ["512"]}
          ])
        end
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
