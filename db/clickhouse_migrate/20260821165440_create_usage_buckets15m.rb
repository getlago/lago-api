# frozen_string_literal: true

class CreateUsageBuckets15m < ActiveRecord::Migration[8.0]
  # Realtime usage on 15-minute buckets of the event timestamp, written by
  # the RisingWave pipeline (extra/risingwave) through a ClickHouse upsert
  # sink. The API serves current usage and wallet refresh by summing buckets
  # over the billing-period window it computes at read time — 15 minutes is
  # the granularity that makes any timezone's day boundary land on a bucket
  # wall (every real UTC offset is a multiple of 15 minutes).
  #
  # RisingWave writes is_deleted (its upsert protocol requires the column);
  # ver is stamped at insert so ReplacingMergeTree keeps the newest version
  # per key. Query with FINAL for exact reads.
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS usage_buckets_15m (
            bucket DateTime64(3),
            organization_id String,
            subscription_id String,
            customer_id String,
            plan_id Nullable(String),
            code String,
            target_wallet_code Nullable(String),
            charge_id String,
            charge_filter_id String,
            grouped_by String,
            aggregation_type String,
            events_count Int64,
            units Decimal(38, 26),
            last_event_at DateTime64(3),
            last_ingested_at DateTime64(3),
            is_deleted UInt8 DEFAULT 0,
            ver DateTime64(3) MATERIALIZED now64(3)
        ) ENGINE = ReplacingMergeTree(ver, is_deleted)
        ORDER BY (organization_id, subscription_id, charge_id, charge_filter_id, grouped_by, bucket)
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS usage_buckets_15m"
    end
  end
end
