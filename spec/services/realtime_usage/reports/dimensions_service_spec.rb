# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::DimensionsService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) do
    described_class.call(organization:, billable_metric:, page:, limit: 2, from_datetime:, to_datetime:)
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:page) { 1 }

  let(:from_datetime) { Time.zone.parse("2026-08-21 09:00:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 11:05:00") }

  include_context "with realtime usage availability"

  def insert_bucket(bucket:, units:, model:)
    create(
      :clickhouse_usage_bucket,
      subscription:,
      customer:,
      organization:,
      billable_metric:,
      charge:,
      bucket: Time.zone.parse(bucket),
      grouped_by: %({"model":"#{model}"}),
      aggregation_type: "count",
      units:
    )
  end

  before do
    insert_bucket(bucket: "2026-08-22 09:30", units: 10, model: "opus")
    insert_bucket(bucket: "2026-08-24 10:30", units: 3, model: "opus")
    insert_bucket(bucket: "2026-08-23 09:30", units: 7, model: "sonnet")
    insert_bucket(bucket: "2026-08-24 09:30", units: 2, model: "haiku")
  end

  it "pages through every dimension, biggest first, with its units per day" do
    expect(result).to be_success
    expect(result.total_count).to eq(3)
    expect(result.dimensions.map { |row| [row.name, row.units.to_f] }).to eq([["opus", 13.0], ["sonnet", 7.0]])
    expect(result.dimensions.first.points.map(&:time)).to eq(
      %w[21 22 23 24].map { |day| Time.zone.parse("2026-08-#{day} 00:00") }
    )
    expect(result.dimensions.map { |row| row.points.map { |point| point.units.to_f } }).to eq([[0.0, 10.0, 0.0, 3.0], [0.0, 0.0, 7.0, 0.0]])
  end

  context "with the next page" do
    let(:page) { 2 }

    it "returns the tail" do
      expect(result.dimensions.map(&:name)).to eq(["haiku"])
      expect(result.dimensions.sole.points.map { |point| point.units.to_f }).to eq([0.0, 0.0, 0.0, 2.0])
    end
  end

  context "with a metric the buckets do not serve" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "unique_count_agg", field_name: "value") }

    it "fails with a validation error" do
      expect(result.error.messages).to eq({billable_metric_code: ["unsupported_aggregation_type"]})
    end
  end
end
