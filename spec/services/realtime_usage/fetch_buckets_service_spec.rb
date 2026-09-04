# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::FetchBucketsService, clickhouse: {clean_before: true} do
  subject(:fetch) { described_class.call(subscription:, boundaries:, charges:) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: 2.months.ago) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:charges) { [charge] }

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

  def create_bucket(bucket:, units: "10.0", events_count: 2, grouped_by: "{}", charge_filter_id: "", billed_charge: nil, **attributes)
    create(
      :clickhouse_usage_bucket,
      organization:, customer:, subscription:, billable_metric:,
      charge: billed_charge || charge,
      bucket:, units:, events_count:, grouped_by:, charge_filter_id:,
      **attributes
    )
  end

  def capture_queries
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      queries << payload[:sql]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
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
      let(:charge) do
        create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "5", "pricing_group_keys" => ["region"]})
      end

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

    context "when the plan carries no servable charge" do
      let(:charges) { [] }

      it "reads nothing" do
        create_bucket(bucket: from_datetime)

        queries = capture_queries { fetch }

        expect(queries.count { |sql| sql.include?("usage_buckets_15m") }).to eq(0)
        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "when clickhouse is unreachable" do
      before do
        allow(Clickhouse::UsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Sentry).to receive(:capture_exception)
      end

      it "returns no bucket, so the computation reads events" do
        expect { fetch }.not_to raise_error
        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "when clickhouse fails before its retries are spent" do
      before do
        failures = 0

        allow(Clickhouse::UsageBucket).to receive(:where).and_wrap_original do |original, *args|
          failures += 1
          raise ActiveRecord::ConnectionNotEstablished if failures == 1

          original.call(*args)
        end
      end

      it "serves the computation, as a transient blip is retried" do
        create_bucket(bucket: from_datetime, units: "10.0", events_count: 2)

        totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

        expect(totals.value).to eq(BigDecimal("10.0"))
      end
    end
  end

  describe "the emitted query" do
    let(:other_charge) { create(:standard_charge, plan:, billable_metric:) }
    let(:charges) { [charge, other_charge] }

    it "seeks the sort order prefix and states the delete marker" do
      create_bucket(bucket: from_datetime)

      queries = capture_queries { fetch }
      sql = queries.find { |query| query.include?("sum(units)") }.delete('"')

      expect(sql).to include("organization_id", "subscription_id", "charge_id IN", "FINAL", "is_deleted")
    end

    it "leaves out the charges the computation is not about" do
      create_bucket(bucket: from_datetime, units: "10.0")
      create_bucket(bucket: from_datetime, units: "7.0", billed_charge: other_charge)

      queries = capture_queries { described_class.call(subscription:, boundaries:, charges: [charge]) }
      sql = queries.find { |query| query.include?("sum(units)") }

      expect(sql).to include(charge.id)
      expect(sql).not_to include(other_charge.id)
    end
  end

  describe "group key drift" do
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "5", "pricing_group_keys" => ["region"]})
    end

    it "serves a charge whose rows carry the keys rails asks for" do
      create_bucket(bucket: from_datetime, grouped_by: {"region" => "eu"}.to_json)

      usage_buckets = fetch.usage_buckets

      expect(usage_buckets.unservable_charge_ids).to be_empty
      expect(usage_buckets.serves_charge?(charge.id)).to be(true)
    end

    it "makes every filter of the charge unservable when a single row drifts" do
      charge_filter = create(:charge_filter, charge:)
      create_bucket(bucket: from_datetime, grouped_by: {"region" => "eu"}.to_json)
      create_bucket(bucket: from_datetime, grouped_by: {"country" => "fr"}.to_json, charge_filter_id: charge_filter.id)

      usage_buckets = fetch.usage_buckets

      expect(usage_buckets.unservable_charge_ids).to eq([charge.id].to_set)
      expect(usage_buckets.serves_charge?(charge.id)).to be(false)
    end

    it "delegates rather than raising on a grouped_by that does not parse" do
      create_bucket(bucket: from_datetime, grouped_by: "{not json")

      expect { fetch }.not_to raise_error
      expect(fetch.usage_buckets.serves_charge?(charge.id)).to be(false)
    end

    it "delegates a row aggregated another way than its metric" do
      create_bucket(bucket: from_datetime, grouped_by: {"region" => "eu"}.to_json, aggregation_type: "count_agg")

      expect(fetch.usage_buckets.serves_charge?(charge.id)).to be(false)
    end

    it "ignores the rows of a charge filter the charge no longer carries" do
      charge_filter = create(:charge_filter, charge:)
      create_bucket(bucket: from_datetime, grouped_by: {"region" => "eu"}.to_json)
      create_bucket(bucket: from_datetime, grouped_by: {"country" => "fr"}.to_json, charge_filter_id: charge_filter.id)
      charge_filter.discard!

      expect(fetch.usage_buckets.serves_charge?(charge.id)).to be(true)
    end

    context "when the charge mixes filters with charge level group keys" do
      it "delegates, because rails groups the events matching no filter and the pipeline does not" do
        create(:charge_filter, charge:, properties: {"amount" => "5"})
        create_bucket(bucket: from_datetime, grouped_by: "{}")

        expect(fetch.usage_buckets.serves_charge?(charge.id)).to be(false)
      end
    end
  end

  describe "the served window" do
    context "when the window starts inside a bucket" do
      let(:from_datetime) { Time.current.beginning_of_day - 1.day + 1.second }

      it "floors the start, so the enclosing bucket is counted" do
        create_bucket(bucket: from_datetime - 1.second, units: "7.0", events_count: 1)

        totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

        expect(totals.value).to eq(BigDecimal("7.0"))
      end
    end

    context "when the window ends inside a bucket" do
      let(:to_datetime) { from_datetime + 1.month - 1.second }

      it "tops the end, so the enclosing bucket is counted" do
        create_bucket(bucket: from_datetime + 1.month - 15.minutes, units: "3.0", events_count: 1)

        totals = fetch.usage_buckets.aggregation_result_for(charge_id: charge.id, charge_filter_id: "")

        expect(totals.value).to eq(BigDecimal("3.0"))
      end
    end

    context "when the window ends on a bucket wall" do
      it "leaves out the bucket opening at the end" do
        create_bucket(bucket: to_datetime, units: "3.0", events_count: 1)

        expect(fetch.usage_buckets).to be_empty
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
