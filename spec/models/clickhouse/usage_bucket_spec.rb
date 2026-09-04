# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::UsageBucket, clickhouse: true do
  subject(:usage_bucket) { create(:clickhouse_usage_bucket) }

  it "persists a record via the factory" do
    expect(described_class.where(organization_id: usage_bucket.organization_id).count).to eq(1)
  end

  describe ".table_name" do
    it "is usage_buckets_15m" do
      expect(described_class.table_name).to eq("usage_buckets_15m")
    end
  end

  describe ".primary_key" do
    it "matches the ClickHouse table primary key" do
      expect(described_class.primary_key).to eq(
        ["organization_id", "subscription_id", "charge_id", "charge_filter_id", "grouped_by", "bucket"]
      )
    end
  end

  describe "the default scope" do
    it "reads with FINAL" do
      expect(described_class.all.to_sql).to include("FINAL")
    end

    it "collapses re-upserted versions of a bucket instead of summing them" do
      bucket = create(:clickhouse_usage_bucket, units: "10.0", events_count: 2, last_ingested_at: 2.minutes.ago)
      reupsert(bucket, units: "25.0", events_count: 5, last_ingested_at: 1.minute.ago)

      rows = described_class.where(organization_id: bucket.organization_id)

      expect(rows.count).to eq(1)
      expect(rows.sum(:units)).to eq(BigDecimal("25.0"))
    end

    it "keeps the version the sink produced last, not the one inserted last" do
      bucket = create(:clickhouse_usage_bucket, units: "25.0", events_count: 5, last_ingested_at: 1.minute.ago)
      reupsert(bucket, units: "10.0", events_count: 2, last_ingested_at: 2.minutes.ago)

      rows = described_class.where(organization_id: bucket.organization_id)

      expect(rows.sum(:units)).to eq(BigDecimal("25.0"))
    end

    def reupsert(bucket, attributes)
      create(
        :clickhouse_usage_bucket,
        organization_id: bucket.organization_id,
        subscription_id: bucket.subscription_id,
        customer_id: bucket.customer_id,
        plan_id: bucket.plan_id,
        code: bucket.code,
        charge_id: bucket.charge_id,
        charge_filter_id: bucket.charge_filter_id,
        grouped_by: bucket.grouped_by,
        aggregation_type: bucket.aggregation_type,
        bucket: bucket.bucket,
        **attributes
      )
    end
  end

  describe "#readonly?" do
    it "is read-only so the RisingWave sink stays the only writer" do
      expect(usage_bucket).to be_readonly
    end

    it "refuses to save" do
      expect { usage_bucket.update(units: "42.0") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "columns" do
    it "keeps units at the Decimal(38, 20) precision the sink writes" do
      bucket = described_class.find_by(organization_id: create(:clickhouse_usage_bucket, units: "0.00000000000000000001").organization_id)

      expect(bucket.units).to eq(BigDecimal("0.00000000000000000001"))
    end

    it "holds a units total wider than a single event value" do
      created = create(:clickhouse_usage_bucket, units: "123456789012345678.0")
      bucket = described_class.find_by(organization_id: created.organization_id)

      expect(bucket.units).to eq(BigDecimal("123456789012345678.0"))
    end

    it "allows plan_id and target_wallet_code to be null" do
      created = create(:clickhouse_usage_bucket, plan_id: nil, target_wallet_code: nil)
      bucket = described_class.find_by(organization_id: created.organization_id)

      expect([bucket.plan_id, bucket.target_wallet_code]).to eq([nil, nil])
    end
  end
end
