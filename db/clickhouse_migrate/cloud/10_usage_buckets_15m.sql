-- Realtime usage on 15-minute buckets of the event timestamp, written by the
-- RisingWave pipeline through a ClickHouse upsert sink. The API serves
-- current usage and wallet refresh by summing buckets over the Rails-computed
-- billing-period window. Query with FINAL for exact reads.
CREATE TABLE IF NOT EXISTS usage_buckets_15m
(
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
)
ENGINE = ReplacingMergeTree(ver, is_deleted)
ORDER BY (organization_id, subscription_id, charge_id, charge_filter_id, grouped_by, bucket);
