# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::BillableMetricsService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) do
    described_class.call(organization:, billable_metrics:, dimension_keys:, from_datetime:, to_datetime:)
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value") }
  let(:billable_metrics) { [billable_metric] }
  let(:dimension_keys) { nil }
  let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us asia]) }

  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:other_plan) { create(:plan, organization:) }
  let(:other_charge) { create(:standard_charge, plan: other_plan, billable_metric:) }
  let(:other_subscription) { create(:subscription, customer:, plan: other_plan) }

  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 11:05:00") }

  include_context "with realtime usage availability"

  def region_filter(charge, value)
    create(:charge_filter, charge:).tap do |charge_filter|
      create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: [value])
    end
  end

  def insert_bucket(bucket:, units:, charge: self.charge, subscription: self.subscription, charge_filter: nil, grouped_by: "{}", billable_metric: self.billable_metric, last_event_at: nil, plan_id: subscription.plan_id)
    create(
      :clickhouse_usage_bucket,
      subscription:,
      customer:,
      organization:,
      billable_metric:,
      charge:,
      plan_id:,
      bucket: Time.zone.parse("2026-08-24 #{bucket}"),
      charge_filter_id: charge_filter&.id || "",
      grouped_by:,
      units:,
      last_event_at: last_event_at || Time.zone.parse("2026-08-24 #{bucket}")
    )
  end

  context "with filters on the same values in two plans" do
    before do
      insert_bucket(bucket: "09:30", units: 10, charge_filter: region_filter(charge, "eu"))
      insert_bucket(bucket: "10:15", units: 5, charge: other_charge, subscription: other_subscription, charge_filter: region_filter(other_charge, "eu"))
      insert_bucket(bucket: "10:30", units: 7, charge_filter: region_filter(charge, "us"))
      insert_bucket(bucket: "10:45", units: 1)
    end

    it "merges them into one dimension, biggest first" do
      report = result.billable_metrics.sole

      expect(report.billable_metric).to eq(billable_metric)
      expect(report.units).to eq(23)
      expect(report.time_granularity).to eq("hour")
      expect(report.dimensions.map { |dimension| [dimension.name, dimension.values, dimension.units.to_f, dimension.other] }).to eq(
        [["eu", {"region" => ["eu"]}, 15.0, false], ["us", {"region" => ["us"]}, 7.0, false], [nil, {}, 1.0, false]]
      )
    end

    it "breaks every period down by dimension" do
      report = result.billable_metrics.sole

      expect(report.points.map(&:time)).to eq([Time.zone.parse("2026-08-24 09:00"), Time.zone.parse("2026-08-24 10:00"), Time.zone.parse("2026-08-24 11:00")])
      expect(report.points.map { |point| point.units.to_f }).to eq([10.0, 13.0, 0.0])
      expect(report.points.map { |point| point.breakdown.map { |usage| usage.units.to_f } }).to eq([[10.0, 0.0, 0.0], [5.0, 7.0, 1.0], [0.0, 0.0, 0.0]])
      expect(report.points.first.breakdown.map(&:dimension_key)).to eq(report.dimensions.map(&:key))
    end

    context "with dimension keys" do
      let(:dimension_keys) do
        described_class.call(organization:, billable_metrics:, from_datetime:, to_datetime:)
          .billable_metrics.sole.dimensions.select { |dimension| dimension.name == "us" }.map(&:key)
      end

      it "only reports them" do
        report = result.billable_metrics.sole

        expect(report.units).to eq(7)
        expect(report.dimensions.map(&:name)).to eq(["us"])
      end
    end
  end

  context "with pricing group keys" do
    before do
      insert_bucket(bucket: "09:30", units: 3, grouped_by: %({"gpu":"a100"}))
      insert_bucket(bucket: "09:45", units: 4, grouped_by: %({"gpu":"h100"}))
    end

    it "splits on their values" do
      expect(result.billable_metrics.sole.dimensions.map { |dimension| [dimension.name, dimension.values] }).to eq(
        [["h100", {"gpu" => ["h100"]}], ["a100", {"gpu" => ["a100"]}]]
      )
    end
  end

  context "with more dimensions than the served series" do
    before do
      stub_const("#{described_class}::MAX_DIMENSIONS", 1)

      insert_bucket(bucket: "09:30", units: 10, charge_filter: region_filter(charge, "eu"))
      insert_bucket(bucket: "09:30", units: 4, charge_filter: region_filter(charge, "us"))
      insert_bucket(bucket: "10:30", units: 2, charge_filter: region_filter(charge, "asia"))
    end

    it "folds the tail into one series that keeps every period summing to its total" do
      report = result.billable_metrics.sole

      expect(report.dimensions.map { |dimension| [dimension.name, dimension.units.to_f, dimension.other] }).to eq(
        [["eu", 10.0, false], [nil, 6.0, true]]
      )
      expect(report.points.map { |point| point.breakdown.map { |usage| usage.units.to_f } }).to eq([[10.0, 4.0], [0.0, 2.0], [0.0, 0.0]])
      expect(report.points.first.breakdown.map(&:dimension_key)).to eq(["{\"region\":[\"eu\"]}\u001F", described_class::OTHER_KEY])
    end

    context "with another metric that does not fold" do
      let(:count_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
      let(:count_charge) { create(:standard_charge, plan:, billable_metric: count_metric) }
      let(:billable_metrics) { [billable_metric, count_metric] }

      before { insert_bucket(bucket: "09:30", units: 3, billable_metric: count_metric, charge: count_charge) }

      it "keeps its dimension as its own series" do
        count_report = result.billable_metrics.last

        expect(result.billable_metrics.first.dimensions.map(&:other)).to eq([false, true])
        expect(count_report.dimensions.map { |dimension| [dimension.key, dimension.units.to_f, dimension.other] }).to eq(
          [[RealtimeUsage::Reports::DimensionKey::SEPARATOR, 3.0, false]]
        )
        expect(count_report.points.map { |point| point.breakdown.map { |usage| usage.units.to_f } }).to eq([[3.0], [0.0], [0.0]])
      end
    end

    context "with a max metric" do
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "max_agg", field_name: "value") }

      before do
        insert_bucket(bucket: "09:45", units: 1, charge_filter: region_filter(charge, "us"))
        insert_bucket(bucket: "10:30", units: 3, charge: other_charge, subscription: other_subscription, charge_filter: region_filter(other_charge, "us"))
      end

      it "folds the sum of the real maxes of the tail" do
        report = result.billable_metrics.sole

        expect(report.dimensions.map { |dimension| [dimension.name, dimension.units.to_f, dimension.other] }).to eq(
          [["eu", 10.0, false], [nil, 9.0, true]]
        )
        expect(report.points.map { |point| point.breakdown.map { |usage| usage.units.to_f } }).to eq([[10.0, 4.0], [0.0, 5.0], [0.0, 0.0]])
      end
    end
  end

  context "with several metrics" do
    let(:count_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:unique_metric) { create(:billable_metric, organization:, aggregation_type: "unique_count_agg", field_name: "value") }
    let(:billable_metrics) { [billable_metric, count_metric, unique_metric] }

    before do
      insert_bucket(bucket: "09:30", units: 10)
      insert_bucket(bucket: "09:30", units: 3, billable_metric: count_metric, charge: create(:standard_charge, plan:, billable_metric: count_metric))
    end

    it "answers every metric the buckets serve, in order, and leaves the others out" do
      expect(result.billable_metrics.map { |report| [report.billable_metric, report.units.to_f] }).to eq(
        [[billable_metric, 10.0], [count_metric, 3.0]]
      )
    end
  end

  context "with sum, max and latest metrics read together" do
    let(:max_metric) { create(:billable_metric, organization:, aggregation_type: "max_agg", field_name: "value") }
    let(:latest_metric) { create(:billable_metric, organization:, aggregation_type: "latest_agg", field_name: "value") }
    let(:max_charge) { create(:standard_charge, plan:, billable_metric: max_metric) }
    let(:latest_charge) { create(:standard_charge, plan:, billable_metric: latest_metric) }
    let(:billable_metrics) { [billable_metric, max_metric, latest_metric] }

    before do
      [[billable_metric, charge], [max_metric, max_charge], [latest_metric, latest_charge]].each do |metric, metric_charge|
        insert_bucket(bucket: "09:30", units: 4, billable_metric: metric, charge: metric_charge)
        insert_bucket(bucket: "09:45", units: 2, billable_metric: metric, charge: metric_charge)
        insert_bucket(bucket: "10:15", units: 3, billable_metric: metric, charge: metric_charge)
      end
    end

    it "aggregates each one as its metric does" do
      expect(result.billable_metrics.map { |report| [report.units.to_f, report.points.map { |point| point.units.to_f }] }).to eq(
        [[9.0, [6.0, 3.0, 0.0]], [4.0, [4.0, 3.0, 0.0]], [3.0, [2.0, 3.0, 0.0]]]
      )
    end
  end

  context "with a plan charging the metric twice" do
    let(:second_charge) { create(:standard_charge, plan:, billable_metric:) }

    before do
      insert_bucket(bucket: "09:30", units: 10)
      insert_bucket(bucket: "09:30", units: 10, charge: second_charge)
    end

    it "counts the usage once" do
      expect(result.billable_metrics.sole.units).to eq(10)
      expect(result.billable_metrics.sole.points.first.units).to eq(10)
    end
  end

  context "with charges of one metric splitting the usage differently" do
    let(:second_charge) { create(:standard_charge, plan:, billable_metric:) }

    before do
      insert_bucket(bucket: "09:30", units: 6, charge_filter: region_filter(charge, "eu"))
      insert_bucket(bucket: "09:30", units: 4)
      insert_bucket(bucket: "09:30", units: 10, charge: second_charge)
    end

    it "reads the charge splitting it the finest, once" do
      report = result.billable_metrics.sole

      expect(report.units).to eq(10)
      expect(report.dimensions.map { |dimension| [dimension.name, dimension.units.to_f] }).to eq([["eu", 6.0], [nil, 4.0]])
      expect(report.points.first.units).to eq(10)
    end

    context "with dimension keys" do
      let(:dimension_keys) { [RealtimeUsage::Reports::DimensionKey::SEPARATOR] }

      it "filters the usage of the charge read" do
        expect(result.billable_metrics.sole.units).to eq(4)
      end
    end
  end

  context "with a subscription whose charge changes in the window" do
    let(:override_charge) { create(:standard_charge, plan: create(:plan, organization:), billable_metric:) }

    before do
      insert_bucket(bucket: "09:30", units: 10, charge_filter: region_filter(charge, "eu"))
      insert_bucket(bucket: "10:30", units: 5, charge: override_charge, plan_id: override_charge.plan_id)
    end

    it "keeps the usage read by both charges" do
      report = result.billable_metrics.sole

      expect(report.units).to eq(15)
      expect(report.points.map { |point| point.units.to_f }).to eq([10.0, 5.0, 0.0])
    end
  end

  context "with the folded series as a dimension key" do
    let(:dimension_keys) { [described_class::OTHER_KEY] }

    it "fails with a validation error" do
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({dimension_keys: ["invalid_dimension_key"]})
    end
  end

  context "with a recurring metric" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value", recurring: true) }

    it "leaves it out" do
      expect(result.billable_metrics).to eq([])
    end
  end

  context "with a max metric" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "max_agg", field_name: "value") }

    before do
      insert_bucket(bucket: "09:30", units: 4)
      insert_bucket(bucket: "09:45", units: 9)
      insert_bucket(bucket: "10:15", units: 6)
      insert_bucket(bucket: "10:30", units: 5, charge: other_charge, subscription: other_subscription)
    end

    it "reads every subscription on its max and adds the subscriptions up" do
      report = result.billable_metrics.sole

      expect(report.points.map { |point| point.units.to_f }).to eq([9.0, 11.0, 0.0])
      expect(report.units).to eq(14)
    end
  end

  context "with a latest metric" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "latest_agg", field_name: "value") }

    before do
      insert_bucket(bucket: "09:30", units: 4)
      insert_bucket(bucket: "09:45", units: 2, last_event_at: Time.zone.parse("2026-08-24 09:50"))
      insert_bucket(bucket: "10:15", units: 7)
      insert_bucket(bucket: "10:30", units: 5, charge: other_charge, subscription: other_subscription)
    end

    it "reads every subscription on its latest value and adds the subscriptions up" do
      report = result.billable_metrics.sole

      expect(report.points.map { |point| point.units.to_f }).to eq([2.0, 12.0, 0.0])
      expect(report.units).to eq(12)
    end
  end

  context "without usage" do
    it "reports empty periods" do
      report = result.billable_metrics.sole

      expect(report.units).to eq(0)
      expect(report.dimensions).to eq([])
      expect(report.points.map { |point| [point.units.to_f, point.breakdown] }).to eq([[0.0, []], [0.0, []], [0.0, []]])
    end
  end

  context "when real-time usage is not enabled for the organization" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "fails with a forbidden error" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end
end
