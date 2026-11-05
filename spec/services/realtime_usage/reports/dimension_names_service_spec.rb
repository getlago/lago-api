# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::DimensionNamesService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) do
    described_class.call(organization:, billable_metric:, limit:, from_datetime:, to_datetime:)
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:limit) { 2 }

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
    insert_bucket(bucket: "2026-07-26 09:30", units: 50, model: "haiku")
    insert_bucket(bucket: "2026-08-22 09:30", units: 10, model: "opus")
    insert_bucket(bucket: "2026-08-24 10:30", units: 3, model: "opus")
    insert_bucket(bucket: "2026-08-23 09:30", units: 7, model: "sonnet")
    insert_bucket(bucket: "2026-08-24 09:30", units: 2, model: "haiku")
  end

  it "lists the biggest dimensions of the window" do
    expect(result).to be_success
    expect(result.dimensions.map(&:name)).to eq(%w[opus sonnet])
    expect(result.dimensions.map(&:key)).to eq(["\u001f{\"model\":\"opus\"}", "\u001f{\"model\":\"sonnet\"}"])
  end

  context "without a start" do
    let(:from_datetime) { nil }
    let(:to_datetime) { nil }
    let(:limit) { nil }

    it "reads the longest window" do
      travel_to(Time.zone.parse("2026-08-24 11:05:00")) do
        expect(result.dimensions.map(&:name)).to eq(%w[haiku opus sonnet])
      end
    end
  end

  context "with a metric the buckets do not serve" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "unique_count_agg", field_name: "value") }

    it "fails with a validation error" do
      expect(result.error.messages).to eq({billable_metric_code: ["unsupported_aggregation_type"]})
    end
  end

  context "with a recurring metric" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value", recurring: true) }

    it "fails with a validation error" do
      expect(result.error.messages).to eq({billable_metric_code: ["unsupported_aggregation_type"]})
    end
  end
end
