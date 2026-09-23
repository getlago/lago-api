# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::ChargeFiltersScan, clickhouse: {clean_before: true} do
  subject(:scan) { described_class.new(charge: loaded_charge) }

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

  let(:charge_properties) { {"amount" => "1"} }
  let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:, properties: charge_properties) }

  let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu apac]) }
  let(:model) { create(:billable_metric_filter, billable_metric:, key: "model", values: %w[a b c]) }

  let(:filter_values) do
    {
      us: {region => %w[us]},
      us_a: {region => %w[us], model => %w[a]},
      b: {model => %w[b]},
      any_region_c: {region => [ChargeFilterValue::ALL_FILTER_VALUES], model => %w[c]}
    }
  end
  let(:filter_properties) { {} }

  let(:events) do
    [
      [{"region" => "us", "model" => "a", "user" => "u1"}, 1],
      [{"region" => "us", "model" => "a", "user" => "u2"}, 2],
      [{"region" => "us", "model" => "b", "user" => "u1"}, 4],
      [{"region" => "us", "model" => "c"}, 8],
      [{"region" => "eu", "model" => "a"}, 16],
      [{"region" => "eu", "model" => "b", "user" => "u2"}, 32],
      [{"region" => "eu", "model" => "c"}, 64],
      [{"region" => "apac"}, 128],
      [{"user" => "u1"}, 256]
    ]
  end

  # Fees::ChargeService reads the charges with their filters preloaded, in one order.
  let(:loaded_charge) { Charge.includes(filters: {values: :billable_metric_filter}).find(charge.id) }
  let(:pricing_buckets) { Fees::ChargeService::Sources::Charge.new(charge: loaded_charge, boundaries: nil).pricing_buckets }

  before do
    filter_values.each do |name, values|
      charge_filter = create(:charge_filter, charge:, properties: charge_properties.merge(filter_properties.fetch(name, {})))

      values.each do |billable_metric_filter, filter_values|
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: filter_values)
      end
    end

    events.each_with_index do |(properties, value), index|
      Clickhouse::EventsEnriched.create!(
        transaction_id: "tr_#{index}",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: boundaries[:from_datetime] + index.hours,
        properties: properties.merge("value" => value.to_s),
        value: value.to_s,
        decimal_value: value.to_d,
        enriched_at: Time.current
      )
    end
  end

  # The store Fees::ChargeService gives the aggregator of each filter.
  def filter_store(item)
    matching_and_ignored = item.matching_and_ignored_filters

    Events::Stores::ClickhouseStore.new(
      code: billable_metric.code,
      billing_context:,
      boundaries:,
      filters: {
        charge_id: charge.id,
        charge_filter: item.charge_filter,
        grouped_by: item.pricing_group_keys.presence,
        matching_filters: matching_and_ignored.matching_filters,
        ignored_filters: matching_and_ignored.ignored_filters
      },
      deduplicate:
    ).tap do |store|
      store.numeric_property = true
      store.aggregation_property = billable_metric.field_name
    end
  end

  def scanned_store(item)
    Events::Stores::ChargeFiltersScanStore.new(filter_store(item), scan:)
  end

  def sorted(grouped_results)
    grouped_results.map(&:to_h).sort_by { it[:groups].to_a.map { |pair| pair.map(&:to_s) } }
  end

  shared_examples "the filter stores" do
    it "sums every filter as its own store does" do
      pricing_buckets.each do |item|
        expect(scanned_store(item).sum).to eq(filter_store(item).sum)
      end
    end

    it "counts every filter as its own store does" do
      pricing_buckets.each do |item|
        expect(scanned_store(item).count).to eq(filter_store(item).count)
      end
    end
  end

  describe "the attribution of the events" do
    it_behaves_like "the filter stores"

    it "reads the events once for every filter of the charge" do
      allow(Events::Stores::Utils::ClickhouseConnection).to receive(:connection_with_retry).and_call_original

      pricing_buckets.each { scanned_store(it).sum }

      expect(Events::Stores::Utils::ClickhouseConnection).to have_received(:connection_with_retry).once
    end

    it "counts an event in each filter it matches" do
      totals = pricing_buckets.to_h { [it.charge_filter.id, scanned_store(it).sum.value] }

      expect(totals.values).to match_array([4, 3, 36, 72, 144 + 256])
    end

    context "without deduplication" do
      let(:deduplicate) { false }

      it_behaves_like "the filter stores"
    end

    context "with a question mark in a filter key" do
      let(:region) { create(:billable_metric_filter, billable_metric:, key: "region?", values: %w[us eu apac]) }
      let(:events) { super().map { |properties, value| [properties.transform_keys("region" => "region?"), value] } }

      it_behaves_like "the filter stores"
    end

    context "with a duplicated event" do
      before do
        Clickhouse::EventsEnriched.create!(
          transaction_id: "tr_0",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: boundaries[:from_datetime],
          properties: {"region" => "eu", "model" => "a", "value" => "1"},
          value: "1",
          decimal_value: 1,
          enriched_at: Time.current + 1.second
        )
      end

      it_behaves_like "the filter stores"
    end
  end

  describe "the batches of filters" do
    before do
      stub_const("#{described_class}::FILTERS_PER_SCAN", 2)
      allow(Events::Stores::Utils::ClickhouseConnection).to receive(:connection_with_retry).and_call_original
    end

    it_behaves_like "the filter stores"

    it "reads the events once per batch" do
      pricing_buckets.each { scanned_store(it).sum }

      expect(Events::Stores::Utils::ClickhouseConnection).to have_received(:connection_with_retry).exactly(3).times
    end

    it "reads only the batch of the filter it aggregates" do
      scanned_store(pricing_buckets.last).sum

      expect(Events::Stores::Utils::ClickhouseConnection).to have_received(:connection_with_retry).once
    end
  end

  describe "the windows" do
    before do
      Clickhouse::EventsEnriched.create!(
        transaction_id: "tr_previous_period",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: boundaries[:from_datetime] - 10.days,
        properties: {"region" => "us", "value" => "512"},
        value: "512",
        decimal_value: 512,
        enriched_at: Time.current
      )
    end

    it "reads the events of the store's window" do
      item = pricing_buckets.find { it.charge_filter.persisted? && it.charge_filter.to_h == {"region" => ["us"]} }

      expect(scanned_store(item).sum.value).to eq(4)
    end

    context "without a lower boundary" do
      it "reads the events from the start, as recurring metrics do" do
        pricing_buckets.each do |item|
          scanned = scanned_store(item).tap { it.use_from_boundary = false }
          store = filter_store(item).tap { it.use_from_boundary = false }

          expect(scanned.sum).to eq(store.sum)
        end
      end

      it "includes the events before the window" do
        item = pricing_buckets.find { it.charge_filter.persisted? && it.charge_filter.to_h == {"region" => ["us"]} }
        scanned = scanned_store(item).tap { it.use_from_boundary = false }

        expect(scanned.sum.value).to eq(4 + 512)
      end
    end
  end

  describe "the groups" do
    let(:charge_properties) { {"amount" => "1", "pricing_group_keys" => ["user"]} }
    let(:filter_properties) { {us_a: {"pricing_group_keys" => %w[user model]}, b: {"pricing_group_keys" => []}} }

    it "groups every filter by its own keys as its own store does" do
      pricing_buckets.each do |item|
        store = filter_store(item)
        next if store.grouped_by.blank?

        expect(sorted(scanned_store(item).grouped_sum)).to eq(sorted(store.grouped_sum))
        expect(sorted(scanned_store(item).grouped_count)).to eq(sorted(store.grouped_count))
      end
    end

    it "sums the filters without groups as their own store does" do
      pricing_buckets.each do |item|
        expect(scanned_store(item).sum).to eq(filter_store(item).sum)
      end
    end
  end

  describe "#covers?" do
    let(:item) { pricing_buckets.first }

    it "covers the stores of the charge's filters" do
      expect(pricing_buckets.map { scan.covers?(filter_store(it)) }).to all(be(true))
    end

    context "when the caller narrowed the store's conditions" do
      it "does not cover the store" do
        store = Events::Stores::ClickhouseStore.new(
          code: billable_metric.code,
          billing_context:,
          boundaries:,
          filters: filter_store(item).filters.merge(matching_filters: {"region" => ["eu"]}),
          deduplicate:
        )

        expect(scan.covers?(store)).to be(false)
      end
    end

    context "when the store groups by a key no filter prices by" do
      it "does not cover the store" do
        store = filter_store(item).tap { it.grouped_by = ["workspace"] }

        expect(scan.covers?(store)).to be(false)
      end
    end
  end

  describe ".supported_charge?" do
    it "supports a sum charge with filters" do
      expect(described_class.supported_charge?(charge)).to be(true)
    end

    context "with a charge without filters" do
      let(:filter_values) { {} }

      it "does not support it" do
        expect(described_class.supported_charge?(loaded_charge)).to be(false)
      end
    end

    context "with a prorated charge" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value", recurring: true) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:, prorated: true, properties: charge_properties) }

      it "does not support it" do
        expect(described_class.supported_charge?(charge)).to be(false)
      end
    end

    context "with a unique count metric" do
      let(:billable_metric) { create(:unique_count_billable_metric, organization:, field_name: "value") }

      it "does not support it" do
        expect(described_class.supported_charge?(charge)).to be(false)
      end
    end
  end
end
