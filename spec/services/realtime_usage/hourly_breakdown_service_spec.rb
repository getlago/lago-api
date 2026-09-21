# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::HourlyBreakdownService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) { described_class.call(subscription:, charge:, from_datetime:, to_datetime:) }

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Europe") }

  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 12:05:00") }

  include_context "with realtime usage availability"

  def insert_bucket(bucket:, units:, events_count: 1, charge_filter_id: "", grouped_by: "{}", ingested_at: nil)
    create(
      :clickhouse_usage_bucket,
      subscription:,
      customer:,
      organization:,
      billable_metric:,
      charge:,
      bucket:,
      charge_filter_id:,
      grouped_by:,
      aggregation_type: "sum",
      events_count:,
      units:,
      last_event_at: bucket,
      last_ingested_at: ingested_at || bucket
    )
  end

  context "with buckets in the window" do
    before do
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), units: 10, charge_filter_id: charge_filter.id)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:45:00"), units: 5, charge_filter_id: charge_filter.id)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 11:00:00"), units: 3)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 12:00:00"), units: 1, charge_filter_id: charge_filter.id)
    end

    it "returns one gap-filled hour per hour of the window" do
      expect(result).to be_success
      expect(result.usage.hours.map(&:time)).to eq(
        [
          Time.zone.parse("2026-08-24 09:00:00"),
          Time.zone.parse("2026-08-24 10:00:00"),
          Time.zone.parse("2026-08-24 11:00:00"),
          Time.zone.parse("2026-08-24 12:00:00")
        ]
      )
      expect(result.usage.hours.map { |hour| hour.units.to_f }).to eq([15.0, 0.0, 3.0, 1.0])
      expect(result.usage.from_datetime).to eq(Time.zone.parse("2026-08-24 09:00:00"))
      expect(result.usage.to_datetime).to eq(Time.zone.parse("2026-08-24 12:15:00"))
    end

    it "breaks every hour down by charge filter, biggest filter first" do
      expect(result.usage.filters.map(&:charge_filter_id)).to eq([charge_filter.id, nil])
      expect(result.usage.filters.map { |filter| filter.units.to_f }).to eq([16.0, 3.0])
      expect(result.usage.filters.map(&:events_count)).to eq([3, 1])
      expect(result.usage.filters.map(&:other)).to eq([false, false])

      expect(result.usage.hours.map { |hour| hour.usages.map { |usage| usage.units.to_f } }).to eq(
        [[15.0, 0.0], [0.0, 0.0], [0.0, 3.0], [1.0, 0.0]]
      )
      expect(result.usage.hours.map { |hour| hour.usages.map(&:charge_filter_id) }.uniq).to eq([[charge_filter.id, nil]])
    end

    it "exposes the aggregation type and the freshest ingestion timestamp" do
      expect(result.usage.aggregation_type).to eq("sum_agg")
      expect(result.usage.timezone).to eq("UTC")
      expect(result.usage.last_ingested_at).to eq(Time.zone.parse("2026-08-24 12:00:00"))
    end
  end

  context "with more filters than the served series" do
    let(:other_filters) { create_list(:charge_filter, 3, charge:) }

    before do
      stub_const("#{described_class}::MAX_FILTERS", 2)

      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), units: 100, charge_filter_id: charge_filter.id)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), units: 50, charge_filter_id: other_filters.first.id)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 10:30:00"), units: 7, charge_filter_id: other_filters.second.id)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 11:30:00"), units: 3, charge_filter_id: other_filters.third.id)
    end

    it "folds every filter past the biggest ones into one series" do
      expect(result.usage.filters.map(&:charge_filter_id)).to eq([charge_filter.id, other_filters.first.id, nil])
      expect(result.usage.filters.map(&:other)).to eq([false, false, true])
      expect(result.usage.filters.map { |filter| filter.units.to_f }).to eq([100.0, 50.0, 10.0])
      expect(result.usage.filters.last.events_count).to eq(2)
    end

    it "keeps every hour to that many series, and sums them to the hour total" do
      expect(result.usage.hours.map { |hour| hour.usages.size }.uniq).to eq([3])
      expect(result.usage.hours.map { |hour| hour.usages.map { |usage| usage.units.to_f } }).to eq(
        [[100.0, 50.0, 0.0], [0.0, 0.0, 7.0], [0.0, 0.0, 3.0], [0.0, 0.0, 0.0]]
      )
      expect(result.usage.hours.map { |hour| hour.units.to_f }).to eq([150.0, 7.0, 3.0, 0.0])
      expect(result.usage.hours.map { |hour| hour.usages.map(&:other) }.uniq).to eq([[false, false, true]])
    end
  end

  context "with buckets outside the window" do
    before do
      insert_bucket(bucket: Time.zone.parse("2026-08-24 08:45:00"), units: 99)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 12:15:00"), units: 77)
    end

    it "ignores them" do
      expect(result.usage.filters).to be_empty
      expect(result.usage.hours.map { |hour| hour.units.to_f }).to eq([0.0, 0.0, 0.0, 0.0])
    end
  end

  context "with several grouped_by rows for the same filter" do
    before do
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), units: 4, grouped_by: '{"region":"eu"}')
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), units: 6, grouped_by: '{"region":"us"}')
    end

    it "sums them into the filter total" do
      expect(result.usage.filters.map { |filter| filter.units.to_f }).to eq([10.0])
      expect(result.usage.hours.first.units.to_f).to eq(10.0)
    end
  end

  context "when the customer timezone is offset by half an hour" do
    let(:customer) { create(:customer, organization:, timezone: "Asia/Kolkata") }

    before do
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:15:00"), units: 2)
      insert_bucket(bucket: Time.zone.parse("2026-08-24 09:45:00"), units: 8)
    end

    it "cuts the hours on the timezone's own walls" do
      expect(result.usage.timezone).to eq("Asia/Kolkata")
      expect(result.usage.hours.first.time).to eq(Time.zone.parse("2026-08-24 08:30:00"))
      expect(result.usage.hours.map { |hour| hour.units.to_f }).to eq([2.0, 8.0, 0.0, 0.0])
    end
  end

  context "when to_datetime sits inside a bucket" do
    let(:to_datetime) { Time.zone.parse("2026-08-24 12:05:00") }

    before { insert_bucket(bucket: Time.zone.parse("2026-08-24 12:00:00"), units: 7) }

    it "reports the end of that bucket, the span the summed units describe" do
      expect(result.usage.to_datetime).to eq(Time.zone.parse("2026-08-24 12:15:00"))
      expect(result.usage.hours.last.units.to_f).to eq(7.0)
    end
  end

  context "when to_datetime sits on a bucket wall" do
    let(:to_datetime) { Time.zone.parse("2026-08-24 12:00:00") }

    before { insert_bucket(bucket: Time.zone.parse("2026-08-24 12:00:00"), units: 7) }

    it "keeps the requested end and leaves out the bucket opening on it" do
      expect(result.usage.to_datetime).to eq(to_datetime)
      expect(result.usage.hours.map(&:time).last).to eq(Time.zone.parse("2026-08-24 11:00:00"))
      expect(result.usage.filters).to be_empty
    end
  end

  context "when clickhouse is unreachable" do
    before do
      allow(Clickhouse::UsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Sentry).to receive(:capture_exception)
    end

    it "fails rather than raising, and reports the outage" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("usage_buckets_read_failure")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(ActiveRecord::ConnectionNotEstablished))
    end
  end

  context "when the window is longer than the cap" do
    let(:to_datetime) { from_datetime + 40.days }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.messages[:to_datetime]).to eq(["window_too_long"])
    end
  end

  context "when realtime usage is not enabled for the organization" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "when the charge is not one the buckets can answer" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "unique_count_agg", field_name: "value") }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "when the charge aggregates values that do not add up across hours" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "max_agg", field_name: "value") }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "when the window is empty" do
    let(:from_datetime) { to_datetime }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.messages[:from_datetime]).to eq(["invalid_window"])
    end
  end
end
