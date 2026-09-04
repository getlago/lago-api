# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::BucketWatermarkService, clickhouse: {clean_before: true} do
  subject(:service) { call_service }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:last_ingested_at) { Time.zone.parse("2026-09-03T10:15:00.250Z") }
  let(:watermark_ms) { (last_ingested_at.to_r * 1000).to_i }

  def call_service(watermarks = [{organization_id: organization.id, subscription_id: subscription.id, watermark_ms:}])
    described_class.call(watermarks:)
  end

  def create_bucket(**attributes)
    create(:clickhouse_usage_bucket, organization:, customer:, subscription:, charge:, billable_metric:, **attributes)
  end

  describe "#call" do
    it "is caught up when a bucket carries the exact watermark millisecond" do
      create_bucket(last_ingested_at:)

      expect(service.caught_up_subscription_ids).to eq(Set[subscription.id])
    end

    it "is caught up when a bucket has moved past the watermark" do
      create_bucket(last_ingested_at: last_ingested_at + 1.second)

      expect(service.caught_up_subscription_ids).to eq(Set[subscription.id])
    end

    it "is not caught up when every bucket is still behind the watermark" do
      create_bucket(last_ingested_at: last_ingested_at - 0.001)

      expect(service.caught_up_subscription_ids).to be_empty
    end

    it "is not caught up when the subscription has no bucket at all" do
      expect(service.caught_up_subscription_ids).to be_empty
    end

    it "ignores the buckets of another subscription of the same organization" do
      other_subscription = create(:subscription, organization:, customer:, plan:)

      create(
        :clickhouse_usage_bucket,
        organization:, customer:, subscription: other_subscription,
        charge:, billable_metric:, last_ingested_at:
      )

      expect(service.caught_up_subscription_ids).to be_empty
    end

    context "with several subscriptions" do
      let(:other_customer) { create(:customer, organization:) }
      let(:other_subscription) { create(:subscription, organization:, customer: other_customer, plan:) }

      let(:watermarks) do
        [
          {organization_id: organization.id, subscription_id: subscription.id, watermark_ms:},
          {organization_id: organization.id, subscription_id: other_subscription.id, watermark_ms:}
        ]
      end

      before do
        create_bucket(last_ingested_at:)

        create(
          :clickhouse_usage_bucket,
          organization:, customer: other_customer, subscription: other_subscription,
          charge:, billable_metric:, last_ingested_at: last_ingested_at - 1.second
        )
      end

      it "returns only the subscriptions whose buckets caught up" do
        expect(call_service(watermarks).caught_up_subscription_ids).to eq(Set[subscription.id])
      end

      # A round-trip per subscription would cost more time than the ingestion this reacts to.
      it "reads every subscription in a single query" do
        reads = 0
        counter = ->(*, payload) { reads += 1 if payload[:sql].to_s.include?("usage_buckets_15m") }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { call_service(watermarks) }

        expect(reads).to eq(1)
      end

      it "waits on the highest watermark of a subscription sent twice" do
        duplicated = [
          {organization_id: organization.id, subscription_id: subscription.id, watermark_ms:},
          {organization_id: organization.id, subscription_id: subscription.id, watermark_ms: watermark_ms + 1_000}
        ]

        expect(call_service(duplicated).caught_up_subscription_ids).to be_empty
      end
    end

    # Karafka consumes inside the Rails executor, so the query cache is on: a read that ran
    # before the bucket landed would otherwise be replayed from cache and never see it.
    it "reads uncached so a read repeated inside one query cache still reaches ClickHouse" do
      create_bucket(last_ingested_at:)

      reads = 0
      counter = lambda do |*, payload|
        reads += 1 if payload[:sql].to_s.include?("usage_buckets_15m") && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Clickhouse::UsageBucket.cache { 2.times { call_service } }
      end

      expect(reads).to eq(2)
    end
  end
end
