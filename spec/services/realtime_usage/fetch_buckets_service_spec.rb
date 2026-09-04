# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::FetchBucketsService, clickhouse: {clean_before: true} do
  subject(:fetch) { described_class.call(subscription:, boundaries:) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: 2.months.ago) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:from_datetime) { Time.current.beginning_of_day - 1.day }
  let(:to_datetime) { from_datetime + 1.month }

  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime:,
      to_datetime:,
      charges_from_datetime: from_datetime,
      charges_to_datetime: to_datetime,
      charges_duration: 30,
      timestamp: Time.current
    )
  end

  def create_bucket(bucket:, units: "10.0", events_count: 2, grouped_by: "{}", charge_filter_id: "", **attributes)
    create(
      :clickhouse_usage_bucket,
      organization:, customer:, subscription:, charge:, billable_metric:,
      bucket:, units:, events_count:, grouped_by:, charge_filter_id:,
      **attributes
    )
  end

  describe "#call" do
    it "sums every bucket of the window into the charge totals" do
      create_bucket(bucket: from_datetime, units: "10.0", events_count: 2)
      create_bucket(bucket: from_datetime + 15.minutes, units: "5.5", events_count: 1)
      create_bucket(bucket: to_datetime + 15.minutes, units: "99.0", events_count: 9)

      totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

      expect(totals.value).to eq(BigDecimal("15.5"))
      expect(totals.events_count).to eq(3)
    end

    it "returns an empty set when the window holds no bucket" do
      expect(fetch.usage_buckets).to be_empty
    end

    it "reads with FINAL, so a re-upserted bucket is not counted twice" do
      create_bucket(bucket: from_datetime, units: "10.0", events_count: 2)
      create_bucket(bucket: from_datetime, units: "12.0", events_count: 3)

      totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

      expect(totals.value).to eq(BigDecimal("12.0"))
      expect(totals.events_count).to eq(3)
    end

    it "ignores the buckets the sink marked as deleted" do
      create_bucket(bucket: from_datetime, units: "10.0", events_count: 2)
      create_bucket(bucket: from_datetime + 15.minutes, units: "7.0", events_count: 1, is_deleted: 1)

      totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

      expect(totals.value).to eq(BigDecimal("10.0"))
    end

    it "keys the totals by charge filter" do
      charge_filter = create(:charge_filter, charge:)
      create_bucket(bucket: from_datetime, units: "10.0", events_count: 2)
      create_bucket(bucket: from_datetime, units: "3.0", events_count: 1, charge_filter_id: charge_filter.id)

      usage_buckets = fetch.usage_buckets

      expect(usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "").value).to eq(BigDecimal("10.0"))
      expect(usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: charge_filter.id).value).to eq(BigDecimal("3.0"))
    end

    context "with grouped buckets" do
      it "returns one result per group, and the total across them" do
        create_bucket(bucket: from_datetime, units: "10.0", events_count: 2, grouped_by: {"region" => "eu"}.to_json)
        create_bucket(bucket: from_datetime + 15.minutes, units: "4.0", events_count: 1, grouped_by: {"region" => "eu"}.to_json)
        create_bucket(bucket: from_datetime, units: "1.0", events_count: 1, grouped_by: {"region" => "us"}.to_json)

        usage_buckets = fetch.usage_buckets
        grouped = usage_buckets.grouped_aggregation_results_for(charge_id: charge.id, charge_filter_id: "")

        expect(grouped.map { [it.groups, it.value, it.events_count] }).to match_array(
          [
            [{"region" => "eu"}, BigDecimal("14.0"), 3],
            [{"region" => "us"}, BigDecimal("1.0"), 1]
          ]
        )
        expect(usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "").value).to eq(BigDecimal("15.0"))
      end

      it "normalizes the absent group value to nil, as the events store returns it" do
        create_bucket(bucket: from_datetime, units: "2.0", events_count: 1, grouped_by: {"region" => ""}.to_json)

        grouped = fetch.usage_buckets.grouped_aggregation_results_for(charge_id: charge.id, charge_filter_id: "")

        expect(grouped.map(&:groups)).to eq([{"region" => nil}])
      end
    end

    context "when the window holds no bucket" do
      it "returns an empty set rather than raising" do
        create_bucket(bucket: from_datetime - 1.day)

        expect(fetch.usage_buckets).to be_empty
      end
    end

    context "when clickhouse is unreachable" do
      before do
        allow(Clickhouse::UsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Sentry).to receive(:capture_exception)
      end

      it "returns no bucket, so the computation reads events" do
        expect(fetch.usage_buckets).to be_nil
      end
    end
  end

  describe "the served window" do
    before { create_bucket(bucket: subscription.started_at.beginning_of_day) }

    context "when the window starts inside a bucket" do
      let(:from_datetime) { Time.current.beginning_of_day - 1.day + 1.second }

      it "returns no bucket, because the enclosing bucket also holds usage of the previous period" do
        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "when the window starts at a 15-minute wall of a shifted timezone" do
      let(:from_datetime) { Time.current.in_time_zone("Asia/Kathmandu").beginning_of_day - 1.day }

      it "is served, as every UTC offset is a multiple of 15 minutes" do
        expect(fetch.usage_buckets).not_to be_nil
      end
    end

    context "when the window starts mid-bucket at the subscription start" do
      let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: 1.month.ago.change(sec: 37)) }
      let(:from_datetime) { subscription.started_at }

      it "is served, as no event before the subscription started lands in that bucket" do
        expect(fetch.usage_buckets).not_to be_nil
      end
    end

    context "when the window end is truncated" do
      before { boundaries.max_timestamp = to_datetime - 1.day }

      it "returns no bucket, because the window ends inside a bucket" do
        expect(fetch.usage_buckets).to be_nil
      end
    end
  end

  describe "the gate" do
    before { create_bucket(bucket: from_datetime) }

    context "when the organization flag is off" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it { expect(fetch.usage_buckets).to be_nil }
    end

    context "when the organization still reads the postgres events store" do
      let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

      it { expect(fetch.usage_buckets).to be_nil }
    end

    context "when the kill switch is off" do
      let(:realtime_usage_enabled) { nil }

      it { expect(fetch.usage_buckets).to be_nil }
    end

    context "when the organization deduplicates its events" do
      let(:organization) do
        create(:organization, feature_flags: ["realtime_usage"], clickhouse_events_store: true, clickhouse_deduplication_enabled: true)
      end

      it "returns no bucket, as the stream and the store disagree by construction" do
        expect(fetch.usage_buckets).to be_nil
      end
    end
  end
end
