# frozen_string_literal: true

require "rails_helper"

# Current usage of a contract served from the product usage buckets RisingWave writes, instead of
# the product events, by Events::Stores::ContractUsageBucketsProvider.
RSpec.describe Contracts::CurrentUsageService, clickhouse: {clean_before: true} do
  subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes: false) }

  include_context "with realtime usage availability"

  let(:feature_flags) { %w[product_catalog realtime_usage] }
  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags:) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:timestamp) { Time.zone.parse("2027-02-10 12:00:00") }
  let(:window_start) { Time.zone.parse("2027-02-01") }

  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:region) { create(:billable_metric_filter, billable_metric:, organization:, key: "region", values: %w[eu us]) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:eu_filter) do
    create(:product_filter, organization:, product:).tap do |filter|
      create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: region, value: "eu")
    end
  end

  let(:default_keys) { ["tier"] }
  let(:default_card) { attach_card(nil, amount: "1", keys: default_keys) }
  let(:eu_card) { attach_card(eu_filter, amount: "10", keys: []) }

  def attach_card(product_filter, amount:, keys:, rate_from: Time.zone.parse("2027-01-01"))
    rate_card = create(:rate_card, organization:, product:, product_filter:, currency: "EUR")
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_from,
      rate_properties: {"amount" => amount, "pricing_group_keys" => keys})
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
  end

  def create_event(timestamp:, region:, tier:)
    create(:clickhouse_product_events_enriched, organization:, external_contract_id: contract.external_id,
      code: billable_metric.code, timestamp:, properties: {"region" => region, "tier" => tier}, value: "1")
  end

  def create_bucket(bucket:, events_count:, product_filter_id: "", grouped_by: "{}")
    create(:clickhouse_product_usage_bucket, contract:, product:, bucket:, product_filter_id:, grouped_by:,
      aggregation_type: "count", units: events_count.to_s, events_count:, last_event_at: bucket)
  end

  def usage_by_card
    result.rate_card_usages.to_h do |usage|
      [usage.contract_rate_card, usage.fees.map { |fee| [fee.grouped_by, fee.units.to_i, fee.amount_cents] }.sort_by(&:to_s)]
    end
  end

  before do
    ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = "product_events_raw"
    default_card
    eu_card
  end

  after { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil }

  context "with the buckets of the events" do
    before do
      create_event(timestamp: window_start + 1.hour, region: "us", tier: "gold")
      create_event(timestamp: window_start + 1.hour + 5.minutes, region: "us", tier: "gold")
      create_event(timestamp: window_start + 2.days, region: "us", tier: "silver")
      create_event(timestamp: window_start + 3.days, region: "eu", tier: "gold")

      create_bucket(bucket: window_start + 1.hour, events_count: 2, grouped_by: '{"tier": "gold"}')
      create_bucket(bucket: window_start + 2.days, events_count: 1, grouped_by: '{"tier": "silver"}')
      create_bucket(bucket: window_start + 3.days, events_count: 1, product_filter_id: eu_filter.id)
    end

    it "prices the same usage as the events" do
      from_buckets = usage_by_card
      ENV["LAGO_REALTIME_USAGE_ENABLED"] = nil
      from_events = described_class.call!(contract:, timestamp:, apply_taxes: false).rate_card_usages.to_h do |usage|
        [usage.contract_rate_card, usage.fees.map { |fee| [fee.grouped_by, fee.units.to_i, fee.amount_cents] }.sort_by(&:to_s)]
      end

      expect(from_buckets).to eq(from_events)
      expect(from_buckets).to eq(
        default_card => [[{"tier" => "gold"}, 2, 200], [{"tier" => "silver"}, 1, 100]],
        eu_card => [[{}, 1, 1000]]
      )
    end
  end

  context "with buckets only" do
    before do
      create_bucket(bucket: window_start, events_count: 5, grouped_by: '{"tier": "gold"}')
      create_bucket(bucket: window_start, events_count: 3, product_filter_id: eu_filter.id)
    end

    it "serves the usage from the buckets" do
      expect(usage_by_card).to eq(
        default_card => [[{"tier" => "gold"}, 5, 500]],
        eu_card => [[{}, 3, 3000]]
      )
    end

    context "when realtime usage is off for the organization" do
      let(:feature_flags) { %w[product_catalog] }

      it "reads the events" do
        expect(usage_by_card.values.flatten(1).sum { it[1] }).to eq(0)
      end
    end

    context "when the buckets group on other keys than the rate" do
      let(:default_keys) { ["model"] }

      it "reads the events of that card" do
        expect(usage_by_card).to eq(default_card => [[{"model" => nil}, 0, 0]], eu_card => [[{}, 3, 3000]])
      end
    end
  end

  context "without any bucket" do
    before { create_event(timestamp: window_start + 1.hour, region: "us", tier: "gold") }

    it "reads the events" do
      expect(usage_by_card[default_card]).to eq([[{"tier" => "gold"}, 1, 100]])
    end
  end
end
