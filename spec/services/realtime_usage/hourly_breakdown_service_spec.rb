# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::HourlyBreakdownService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) { described_class.call(subscription:, charge:, from_datetime:, to_datetime:) }

  let(:billable_metric) { create(:billable_metric, aggregation_type: "sum_agg", field_name: "value") }
  let(:organization) { billable_metric.organization }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Europe") }

  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 12:05:00") }

  def insert_bucket(bucket:, units:, events_count: 1, charge_filter_id: "", grouped_by: "{}", ingested_at: nil)
    Clickhouse::UsageBucket.insert_all([
      {
        bucket:,
        organization_id: organization.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        plan_id: plan.id,
        code: billable_metric.code,
        charge_id: charge.id,
        charge_filter_id:,
        grouped_by:,
        aggregation_type: "sum",
        events_count:,
        units:,
        last_event_at: bucket,
        last_ingested_at: ingested_at || bucket
      }
    ])
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
      expect(result.usage.to_datetime).to eq(to_datetime)
    end

    it "breaks every hour down by charge filter, biggest filter first" do
      expect(result.usage.filters.map(&:charge_filter_id)).to eq([charge_filter.id, nil])
      expect(result.usage.filters.map { |filter| filter.units.to_f }).to eq([16.0, 3.0])
      expect(result.usage.filters.map(&:events_count)).to eq([3, 1])

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

  context "when the window is empty" do
    let(:from_datetime) { to_datetime }

    it "fails" do
      expect(result).not_to be_success
      expect(result.error.messages[:from_datetime]).to eq(["invalid_window"])
    end
  end
end
