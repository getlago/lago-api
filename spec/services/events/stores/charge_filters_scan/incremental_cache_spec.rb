# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::ChargeFiltersScan::IncrementalCache, clickhouse: {clean_before: true} do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
  let(:plan) { create(:plan, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: Time.zone.parse("2026-01-01")) }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:boundaries) do
    {
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime: Time.zone.parse("2026-09-30").end_of_day,
      charges_duration: 30
    }
  end
  let(:deduplicate) { true }

  # 12:07 puts the cut at 11:45: a quarter of an hour behind, rounded down.
  let(:now) { Time.zone.parse("2026-09-15 12:07:00") }
  let(:cut) { Time.zone.parse("2026-09-15 11:45:00") }

  let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:, properties: {"amount" => "1"}) }
  let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }

  let(:filter_values) { %w[us eu] }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:reads) { [] }

  let(:events) do
    [
      ["tr_1", Time.zone.parse("2026-09-02 10:00"), "us", 1],
      ["tr_2", Time.zone.parse("2026-09-10 10:00"), "eu", 2],
      ["tr_3", Time.zone.parse("2026-09-15 11:30"), "us", 4],
      ["tr_4", Time.zone.parse("2026-09-15 11:50"), "eu", 8],
      ["tr_5", Time.zone.parse("2026-09-15 12:00"), "us", 16]
    ]
  end

  def ingest(transaction_id, timestamp, region, value, enriched_at: Time.current)
    Clickhouse::EventsEnriched.create!(
      transaction_id:,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp:,
      properties: {"region" => region, "value" => value.to_s},
      value: value.to_s,
      decimal_value: value.to_d,
      enriched_at:
    )
  end

  # The filters Fees::ChargeService gives the store, which names neither a filter nor conditions
  # for a charge without filters.
  def store_filters(item)
    return {charge_id: charge.id, grouped_by: item.pricing_group_keys.presence} if item.charge_filter.nil?

    matching_and_ignored = item.matching_and_ignored_filters

    {
      charge_id: charge.id,
      charge_filter: item.charge_filter,
      grouped_by: item.pricing_group_keys.presence,
      matching_filters: matching_and_ignored.matching_filters,
      ignored_filters: matching_and_ignored.ignored_filters
    }
  end

  def filter_store(item)
    Events::Stores::ClickhouseStore.new(
      code: billable_metric.code,
      billing_context:,
      boundaries:,
      filters: store_filters(item),
      deduplicate:
    ).tap do |store|
      store.numeric_property = true
      store.aggregation_property = billable_metric.field_name
    end
  end

  # One current usage computation: the charge read again with its filters and a new scan, as
  # Fees::ChargeService does on each call.
  def totals(incremental: true, filter_ids: nil)
    loaded_charge = Charge.includes(filters: {values: :billable_metric_filter}).find(charge.id)
    cache = (described_class.new(subscription:, charge: loaded_charge) if incremental)
    scan = Events::Stores::ChargeFiltersScan.new(charge: loaded_charge, filter_ids:, incremental: cache)
    pricing_buckets = Fees::ChargeService::Sources::Charge.new(charge: loaded_charge, boundaries: nil).pricing_buckets

    pricing_buckets.to_h do |item|
      [item.charge_filter&.id, aggregate(Events::Stores::ChargeFiltersScanStore.new(filter_store(item), scan:)).to_h]
    end
  end

  def aggregate(store)
    case billable_metric.aggregation_type
    when "max_agg" then store.max
    when "latest_agg" then store.last
    else store.sum
    end
  end

  def computation
    reads.clear
    totals
  end

  before do
    filter_values.each do |value|
      charge_filter = create(:charge_filter, charge:, properties: {"amount" => "1"})
      create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: [value])
    end

    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(described_class).to receive(:new).and_wrap_original do |method, **args|
      method.call(**args).tap do |cache|
        allow(cache).to receive(:rows).and_wrap_original do |rows, **kwargs, &read|
          rows.call(**kwargs) do |**window|
            reads << window
            read.call(**window)
          end
        end
      end
    end

    travel_to(now - 1.hour) do
      events.each { |transaction_id, timestamp, region, value| ingest(transaction_id, timestamp, region, value) }
    end

    travel_to(now)
  end

  it "answers the plain scan's totals, reading the base and the tail" do
    expect(computation).to eq(totals(incremental: false))
    expect(reads).to eq(
      [
        {from_datetime: boundaries[:from_datetime], to_datetime: nil, before: cut},
        {from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}
      ]
    )
  end

  context "when the base was kept by a previous computation" do
    before do
      computation
      ingest("tr_6", Time.zone.parse("2026-09-15 12:05"), "eu", 32)
    end

    it "reads the tail only" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads).to eq([{from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end

  context "when the cut moved forward" do
    before do
      computation
      travel_to(now + 15.minutes)
      ingest("tr_6", Time.zone.parse("2026-09-15 12:10"), "eu", 32)
    end

    it "adds the slice between the two cuts to the base" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads).to eq(
        [
          {from_datetime: cut, to_datetime: nil, before: cut + 15.minutes},
          {from_datetime: cut + 15.minutes, to_datetime: boundaries[:to_datetime], before: nil}
        ]
      )
    end
  end

  context "when an event older than the cut was ingested after the base" do
    before do
      computation
      ingest("tr_late", Time.zone.parse("2026-09-03 10:00"), "us", 64)
    end

    it "reads the base again" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads.first).to eq({from_datetime: boundaries[:from_datetime], to_datetime: nil, before: cut})
    end
  end

  context "when an event of the base is replaced by a copy" do
    before do
      computation
      ingest("tr_1", Time.zone.parse("2026-09-02 10:00"), "eu", 128)
    end

    it "reads the base again and counts the copy only" do
      expect(computation).to eq(totals(incremental: false))
      expect(computation.values.sum { it[:value] }).to eq(2 + 4 + 8 + 16 + 128)
    end
  end

  context "when the events were changed without being ingested" do
    before do
      computation
      Subscriptions::ChargeCacheService.expire_for_subscription_charge(subscription:, charge:)
    end

    it "reads the base again" do
      computation

      expect(reads.first).to eq({from_datetime: boundaries[:from_datetime], to_datetime: nil, before: cut})
    end

    it "forgets the generation after the full refresh interval" do
      key = described_class.generation_key(subscription.id, charge.id)

      travel_to(now + described_class::FULL_REFRESH_INTERVAL + 1.second) do
        expect(Rails.cache.read(key)).to be_nil
      end
    end
  end

  context "when the metric filter values are edited" do
    # A filter taking every region besides the us one: its conditions follow the metric filter.
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu apac]) }
    let(:filter_values) { ["us", ChargeFilterValue::ALL_FILTER_VALUES] }
    let(:events) { super() + [["tr_apac", Time.zone.parse("2026-09-05 10:00"), "apac", 64]] }

    before do
      computation

      # Trims the values of the metric filter, which touches neither the charge, its filters nor
      # the metric: the filter taking all values now ignores the apac events.
      BillableMetricFilters::CreateOrUpdateBatchService.call!(
        billable_metric:,
        filters_params: [{key: "region", values: %w[us eu]}]
      )
    end

    it "reads the base again under the new conditions" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads.first).to eq({from_datetime: boundaries[:from_datetime], to_datetime: nil, before: cut})
    end
  end

  context "when the pre-filter answers the filters to aggregate in another order" do
    let(:filter_ids) { charge.filters.map(&:id) + [nil] }

    before do
      reads.clear
      totals(filter_ids:)
    end

    it "keeps the base" do
      reads.clear

      expect(totals(filter_ids: filter_ids.reverse)).to eq(totals(incremental: false))
      expect(reads).to eq([{from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end

  context "when a charge filter value is edited without touching the charge" do
    before do
      computation

      # As the bulk edits of filter values do (update_all), leaving every timestamp of the cache key.
      ChargeFilterValue.where(values: ["eu"]).update_all(values: %w[eu us]) # rubocop:disable Rails/SkipsModelValidations
    end

    it "reads the base again under the new conditions" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads.first).to eq({from_datetime: boundaries[:from_datetime], to_datetime: nil, before: cut})
    end
  end

  context "when the base is older than the full refresh interval" do
    before do
      computation
      travel_to(now + described_class::FULL_REFRESH_INTERVAL)
    end

    it "reads the base again" do
      computation

      expect(reads.first).to eq({from_datetime: boundaries[:from_datetime], to_datetime: nil, before: Time.zone.parse("2026-09-15 17:45")})
    end
  end

  context "with a charge without filters" do
    let(:filter_values) { [] }

    before do
      computation
      ingest("tr_6", Time.zone.parse("2026-09-15 12:05"), "eu", 32)
    end

    it "keeps the totals of its default bucket" do
      expect(computation).to eq(totals(incremental: false))
      expect(computation).to eq({nil => {value: 63, events_count: 6}})
      expect(reads).to eq([{from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end

  context "with a max charge" do
    let(:billable_metric) { create(:max_billable_metric, organization:, field_name: "value") }

    # The largest events of each filter are in the base.
    let(:events) do
      [
        ["tr_1", Time.zone.parse("2026-09-02 10:00"), "us", 16],
        ["tr_2", Time.zone.parse("2026-09-10 10:00"), "eu", 8],
        ["tr_3", Time.zone.parse("2026-09-15 11:30"), "us", 4],
        ["tr_4", Time.zone.parse("2026-09-15 11:50"), "eu", 2],
        ["tr_5", Time.zone.parse("2026-09-15 12:00"), "us", 1]
      ]
    end

    before do
      computation
      ingest("tr_6", Time.zone.parse("2026-09-15 12:05"), "eu", 32)
    end

    it "keeps the max of the base and adds the tail's" do
      expect(computation).to eq(totals(incremental: false))
      expect(computation.values).to match_array([{value: 16, events_count: 3}, {value: 32, events_count: 3}, {value: 0, events_count: 0}])
      expect(reads).to eq([{from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end

  context "with a latest charge" do
    let(:billable_metric) { create(:latest_billable_metric, organization:, field_name: "value") }

    # Every event of the eu filter is in the base.
    let(:events) do
      [
        ["tr_1", Time.zone.parse("2026-09-02 10:00"), "us", 1],
        ["tr_2", Time.zone.parse("2026-09-10 10:00"), "eu", 2],
        ["tr_3", Time.zone.parse("2026-09-15 11:30"), "us", 4],
        ["tr_5", Time.zone.parse("2026-09-15 12:00"), "us", 16]
      ]
    end

    before do
      computation
      ingest("tr_6", Time.zone.parse("2026-09-15 12:05"), "us", 3)
    end

    it "answers the latest value of the tail, or of the base without one" do
      expect(computation).to eq(totals(incremental: false))
      expect(computation.values).to match_array([{value: 3, events_count: 4}, {value: 2, events_count: 1}, {value: nil, events_count: 0}])
      expect(reads).to eq([{from_datetime: cut, to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end

  context "without deduplication" do
    let(:deduplicate) { false }

    before { computation }

    it "answers the plain scan's totals" do
      expect(computation).to eq(totals(incremental: false))
    end
  end

  context "when the window starts after the cut" do
    let(:boundaries) do
      {from_datetime: Time.zone.parse("2026-09-15 12:00"), to_datetime: Time.zone.parse("2026-09-30").end_of_day, charges_duration: 15}
    end

    it "reads the window as a whole" do
      expect(computation).to eq(totals(incremental: false))
      expect(reads).to eq([{from_datetime: boundaries[:from_datetime], to_datetime: boundaries[:to_datetime], before: nil}])
    end
  end
end
