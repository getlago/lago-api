CREATE TABLE default.usage_buckets_15m
(
    `bucket` DateTime64(3),
    `organization_id` String,
    `subscription_id` String,
    `customer_id` String,
    `plan_id` Nullable(String),
    `code` String,
    `target_wallet_code` Nullable(String),
    `charge_id` String,
    `charge_filter_id` String,
    `grouped_by` String,
    `aggregation_type` String,
    `events_count` Int64,
    `units` Decimal(38, 20),
    `last_event_at` DateTime64(3),
    `last_ingested_at` DateTime64(3),
    `is_deleted` UInt8 DEFAULT 0
)
ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', last_ingested_at, is_deleted)
PARTITION BY toYYYYMM(bucket)
ORDER BY (organization_id, subscription_id, charge_id, charge_filter_id, grouped_by, bucket)
SETTINGS index_granularity = 8192
