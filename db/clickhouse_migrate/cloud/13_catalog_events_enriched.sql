CREATE TABLE default.catalog_events_enriched
(
    `organization_id` String,
    `external_contract_id` String,
    `contract_id` Nullable(String),
    `code` String,
    `timestamp` DateTime64(3),
    `transaction_id` String,
    `properties` Map(String, String),
    `sorted_properties` Map(String, String) DEFAULT mapSort(properties),
    `value` Nullable(String),
    `decimal_value` Nullable(Decimal(38, 26)) DEFAULT toDecimal128OrZero(value, 26),
    `precise_total_amount_cents` Nullable(Decimal(40, 15)),
    `attribution_labels` Map(String, String),
    `enriched_at` DateTime64(3) DEFAULT now64(3)
)
ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', enriched_at)
PRIMARY KEY (organization_id, code, external_contract_id, toDate(timestamp))
ORDER BY (organization_id, code, external_contract_id, toDate(timestamp), timestamp, transaction_id)
SETTINGS index_granularity = 8192
