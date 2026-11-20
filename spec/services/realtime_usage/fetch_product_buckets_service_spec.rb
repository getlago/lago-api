# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::FetchProductBucketsService, clickhouse: {clean_before: true} do
  subject(:fetch) { described_class.call(contract:, from_datetime:, to_datetime:) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: %w[product_catalog realtime_usage])
  end
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }

  let(:from_datetime) { Time.zone.parse("2027-02-01") }
  let(:to_datetime) { Time.zone.parse("2027-03-01") }

  def create_bucket(bucket:, units: "10.0", events_count: 2, grouped_by: "{}", product_filter_id: "", **attributes)
    create(
      :clickhouse_product_usage_bucket,
      contract:, product:,
      bucket:, units:, events_count:, grouped_by:, product_filter_id:,
      aggregation_type: "sum",
      last_event_at: bucket,
      **attributes
    )
  end

  it "sums the buckets of the window per product and product filter" do
    create_bucket(bucket: from_datetime, units: "3.0", events_count: 1, precise_total_amount_cents: "2.5")
    create_bucket(bucket: from_datetime + 15.minutes, units: "4.0", events_count: 2, precise_total_amount_cents: "1.5")
    create_bucket(bucket: from_datetime, units: "7.0", events_count: 3, product_filter_id: "filter-1")

    set = fetch.usage_buckets

    expect(set.aggregation_result_for(charge_id: product.id, charge_filter_id: ""))
      .to eq(Events::Stores::BaseStore::AggregationResult.new(value: 7, events_count: 3))
    expect(set.precise_total_amount_cents_for(charge_id: product.id, charge_filter_id: "")).to eq(4)
    expect(set.aggregation_result_for(charge_id: product.id, charge_filter_id: "filter-1"))
      .to eq(Events::Stores::BaseStore::AggregationResult.new(value: 7, events_count: 3))
  end

  it "reads the window with its end excluded" do
    create_bucket(bucket: from_datetime - 15.minutes, units: "100.0")
    create_bucket(bucket: from_datetime, units: "1.0", events_count: 1)
    create_bucket(bucket: to_datetime - 15.minutes, units: "2.0", events_count: 1)
    create_bucket(bucket: to_datetime, units: "100.0")

    expect(fetch.usage_buckets.aggregation_result_for(charge_id: product.id, charge_filter_id: "").value).to eq(3)
  end

  it "reads every product of the contract only" do
    other_contract = create(:contract, organization:, customer:)
    other_product = create(:product, :metered, organization:, billable_metric:)
    create_bucket(bucket: from_datetime, units: "1.0", events_count: 1)
    create(:clickhouse_product_usage_bucket, contract: other_contract, product:, bucket: from_datetime, units: "100.0")
    create(:clickhouse_product_usage_bucket, contract:, product: other_product, bucket: from_datetime, units: "5.0")

    set = fetch.usage_buckets

    expect(set.aggregation_result_for(charge_id: product.id, charge_filter_id: "").value).to eq(1)
    expect(set.aggregation_result_for(charge_id: other_product.id, charge_filter_id: "").value).to eq(5)
  end

  it "groups the usage and lists the group keys of each product filter" do
    create_bucket(bucket: from_datetime, units: "1.0", events_count: 1, grouped_by: '{"region": "eu"}')
    create_bucket(bucket: from_datetime + 15.minutes, units: "2.0", events_count: 1, grouped_by: '{"region": "eu"}')
    create_bucket(bucket: from_datetime, units: "4.0", events_count: 1, grouped_by: '{"region": ""}')

    groups = fetch.usage_buckets.grouped_aggregation_results_for(charge_id: product.id, charge_filter_id: "")

    expect(groups).to contain_exactly(
      Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"region" => "eu"}, value: 3, events_count: 2),
      Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"region" => nil}, value: 4, events_count: 1)
    )
    expect(fetch.group_keys).to eq({[product.id, ""] => Set[["region"]]})
  end

  it "lists every set of group keys the rows carry" do
    create_bucket(bucket: from_datetime, grouped_by: '{"region": "eu"}')
    create_bucket(bucket: from_datetime + 15.minutes, grouped_by: "{}")

    expect(fetch.group_keys).to eq({[product.id, ""] => Set[["region"], []]})
  end

  context "with a max metric" do
    let(:billable_metric) { create(:max_billable_metric, organization:) }

    it "takes the highest bucket" do
      create_bucket(bucket: from_datetime, units: "3.0", aggregation_type: "max")
      create_bucket(bucket: from_datetime + 15.minutes, units: "9.0", aggregation_type: "max")

      expect(fetch.usage_buckets.aggregation_result_for(charge_id: product.id, charge_filter_id: "").value).to eq(9)
    end
  end

  context "with a latest metric" do
    let(:billable_metric) { create(:latest_billable_metric, organization:) }

    it "takes the last bucket" do
      create_bucket(bucket: from_datetime + 15.minutes, units: "3.0", aggregation_type: "latest")
      create_bucket(bucket: from_datetime, units: "9.0", aggregation_type: "latest")

      expect(fetch.usage_buckets.aggregation_result_for(charge_id: product.id, charge_filter_id: "").value).to eq(3)
    end
  end

  context "when realtime usage is off for the organization" do
    let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: %w[product_catalog]) }

    it "returns no set" do
      create_bucket(bucket: from_datetime)

      expect(fetch).to be_success
      expect(fetch.usage_buckets).to be_nil
    end
  end

  context "when ClickHouse cannot be read" do
    before do
      allow(Clickhouse::ProductUsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Sentry).to receive(:capture_exception)
    end

    it "fails without raising" do
      expect(fetch).to be_failure
      expect(fetch.error.code).to eq("usage_buckets_read_failure")
      expect(Sentry).to have_received(:capture_exception)
    end
  end
end
