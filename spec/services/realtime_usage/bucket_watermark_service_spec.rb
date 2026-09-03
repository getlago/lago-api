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

  def call_service
    described_class.call(organization_id: organization.id, subscription_id: subscription.id, watermark_ms:)
  end

  def create_bucket(**attributes)
    create(:clickhouse_usage_bucket, organization:, customer:, subscription:, charge:, billable_metric:, **attributes)
  end

  describe "#call" do
    it "is reached when a bucket carries the exact watermark millisecond" do
      create_bucket(last_ingested_at:)

      expect(service.reached).to be(true)
    end

    it "is reached when a bucket has moved past the watermark" do
      create_bucket(last_ingested_at: last_ingested_at + 1.second)

      expect(service.reached).to be(true)
    end

    it "is not reached when every bucket is still behind the watermark" do
      create_bucket(last_ingested_at: last_ingested_at - 0.001)

      expect(service.reached).to be(false)
    end

    it "is not reached when the subscription has no bucket at all" do
      expect(service.reached).to be(false)
    end

    it "ignores the buckets of another subscription of the same organization" do
      other_subscription = create(:subscription, organization:, customer:, plan:)

      create(
        :clickhouse_usage_bucket,
        organization:, customer:, subscription: other_subscription,
        charge:, billable_metric:, last_ingested_at:
      )

      expect(service.reached).to be(false)
    end

    # Karafka consumes inside the Rails executor, so the query cache is on: a poll that ran
    # before the bucket landed would otherwise be replayed from cache and never see it.
    it "reads uncached so a poll repeated inside one query cache still reaches ClickHouse" do
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
