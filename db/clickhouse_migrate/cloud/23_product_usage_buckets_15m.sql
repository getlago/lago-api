CREATE TABLE default.product_usage_buckets_15m
(
    `bucket` DateTime64(3),
    `organization_id` String,
    `contract_id` String,
    `customer_id` String,
    `code` String,
    `product_id` String,
    `product_filter_id` String,
    `grouped_by` String,
    `aggregation_type` String,
    `events_count` Int64,
    `units` Decimal(38, 20),
    `precise_total_amount_cents` Decimal(38, 15) DEFAULT 0,
    `last_event_at` DateTime64(3),
    `last_ingested_at` DateTime64(3),
    `is_deleted` UInt8 DEFAULT 0,
    `ver` DateTime64(3) MATERIALIZED now64(3)
)
ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', ver, is_deleted)
PARTITION BY toYYYYMM(bucket)
ORDER BY (organization_id, contract_id, product_id, product_filter_id, grouped_by, bucket)
SETTINGS index_granularity = 8192
