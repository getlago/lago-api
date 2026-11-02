# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::EventsService, clickhouse: {clean_before: true}, transaction: false do
  subject(:result) do
    described_class.call(organization:, external_customer_id:, external_subscription_id:, from_datetime:, to_datetime:)
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:external_customer_id) { nil }
  let(:external_subscription_id) { nil }

  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 12:05:00") }

  include_context "with realtime usage availability"

  def insert_bucket(bucket:, events_count:, charge: self.charge, subscription: self.subscription, is_deleted: 0, ingested_at: bucket)
    create(
      :clickhouse_usage_bucket,
      subscription:,
      customer: subscription.customer,
      organization:,
      billable_metric:,
      charge:,
      bucket:,
      aggregation_type: "count",
      events_count:,
      units: events_count,
      last_ingested_at: ingested_at,
      is_deleted:
    )
  end

  before do
    insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), events_count: 4)
    insert_bucket(bucket: Time.zone.parse("2026-08-24 09:45:00"), events_count: 2, ingested_at: Time.zone.parse("2026-08-24 09:46:00"))
    insert_bucket(bucket: Time.zone.parse("2026-08-24 11:15:00"), events_count: 3)
    insert_bucket(bucket: Time.zone.parse("2026-08-24 11:30:00"), events_count: 50, is_deleted: 1)
    insert_bucket(bucket: Time.zone.parse("2026-08-24 12:15:00"), events_count: 70)
  end

  it "counts the events of every period of the window" do
    expect(result).to be_success
    expect(result.events.points.map(&:time)).to eq(
      ["09:00", "10:00", "11:00", "12:00"].map { |hour| Time.zone.parse("2026-08-24 #{hour}:00") }
    )
    expect(result.events.points.map(&:events_count)).to eq([6, 0, 3, 0])
    expect(result.events.events_count).to eq(9)
    expect(result.events.time_granularity).to eq("hour")
    expect(result.events.timezone).to eq("UTC")
    expect(result.events.last_ingested_at).to eq(Time.zone.parse("2026-08-24 11:15:00"))
  end

  context "with two charges of the same metric on a plan" do
    let(:second_charge) { create(:standard_charge, plan:, billable_metric:) }

    before { insert_bucket(bucket: Time.zone.parse("2026-08-24 09:30:00"), events_count: 4, charge: second_charge) }

    it "counts their events once" do
      expect(result.events.points.map(&:events_count)).to eq([6, 0, 3, 0])
    end
  end

  context "without buckets in the window" do
    let(:from_datetime) { Time.zone.parse("2026-08-25 09:00:00") }
    let(:to_datetime) { Time.zone.parse("2026-08-25 10:00:00") }

    it "has no last ingestion" do
      expect(result.events.events_count).to eq(0)
      expect(result.events.last_ingested_at).to be_nil
    end
  end

  context "with a customer" do
    let(:other_subscription) { create(:subscription, customer: create(:customer, organization:), plan:) }
    let(:external_customer_id) { customer.external_id }

    before { insert_bucket(bucket: Time.zone.parse("2026-08-24 10:00:00"), events_count: 8, subscription: other_subscription) }

    it "only counts its events" do
      expect(result.events.events_count).to eq(9)
    end

    context "when the customer is deleted" do
      before { customer.discard! }

      it "still counts its events" do
        expect(result.events.events_count).to eq(9)
      end
    end
  end

  context "with a subscription" do
    let(:other_subscription) { create(:subscription, customer:, plan:) }
    let(:external_subscription_id) { subscription.external_id }

    before { insert_bucket(bucket: Time.zone.parse("2026-08-24 10:00:00"), events_count: 8, subscription: other_subscription) }

    it "only counts its events, not those of the customer's other subscriptions" do
      expect(result.events.events_count).to eq(9)
    end
  end

  context "when ClickHouse fails" do
    let(:error) { RealtimeUsage::READ_ERRORS.first.new("connection refused") }

    before do
      allow(Clickhouse::UsageBucket.connection).to receive(:select_rows).and_raise(error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "fails with a service failure and reports the error" do
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("usage_buckets_read_failure")
      expect(Sentry).to have_received(:capture_exception).with(error)
    end
  end

  context "with another organization's buckets" do
    let(:other_subscription) { create(:subscription) }

    before do
      create(:clickhouse_usage_bucket, subscription: other_subscription, customer: other_subscription.customer,
        bucket: Time.zone.parse("2026-08-24 10:00:00"), events_count: 8)
    end

    it "ignores them" do
      expect(result.events.events_count).to eq(9)
    end
  end

  context "when real-time usage is not enabled for the organization" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "fails with a forbidden error" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "with a window longer than the maximum" do
    let(:to_datetime) { from_datetime + 32.days }

    it "fails with a validation error" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({to_datetime: ["window_too_long"]})
    end
  end
end
