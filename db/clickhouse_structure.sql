CREATE TABLE events_enriched ( `organization_id` String, `external_subscription_id` String, `code` String, `timestamp` DateTime64(3), `transaction_id` String, `properties` Map(String, String), `sorted_properties` Map(String, String) DEFAULT mapSort(properties), `value` Nullable(String), `decimal_value` Nullable(Decimal(38, 26)) DEFAULT toDecimal128OrZero(value, 26), `enriched_at` DateTime64(3) DEFAULT now(), `precise_total_amount_cents` Nullable(Decimal(40, 15)) ) ENGINE = ReplacingMergeTree(timestamp) PRIMARY KEY (organization_id, code, external_subscription_id, toDate(timestamp)) ORDER BY (organization_id, code, external_subscription_id, toDate(timestamp), timestamp, transaction_id) SETTINGS index_granularity = 8192;

CREATE TABLE events_enriched_queue ( `organization_id` String, `external_subscription_id` String, `code` String, `timestamp` String, `transaction_id` String, `properties` String, `value` Nullable(String), `precise_total_amount_cents` Nullable(Decimal(40, 15)) ) ENGINE = Kafka SETTINGS kafka_broker_list = 'redpanda:9092', kafka_topic_list = 'events_enriched', kafka_group_name = 'clickhouse', kafka_format = 'JSONEachRow';

CREATE TABLE events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String), `precise_total_amount_cents` Nullable(Decimal(40, 15)), `ingested_at` DateTime64(3) ) ENGINE = MergeTree ORDER BY (organization_id, external_subscription_id, code, transaction_id, timestamp) SETTINGS index_granularity = 8192;

CREATE TABLE events_raw_queue ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` String, `code` String, `properties` String, `precise_total_amount_cents` Nullable(Decimal(40, 15)), `ingested_at` DateTime64(3) ) ENGINE = Kafka SETTINGS kafka_broker_list = 'redpanda:9092', kafka_topic_list = 'events-raw', kafka_group_name = 'clickhouse', kafka_format = 'JSONEachRow';

CREATE MATERIALIZED VIEW events_enriched_mv TO events_enriched ( `organization_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String), `value` Nullable(String), `precise_total_amount_cents` Nullable(Decimal(40, 15)) ) AS SELECT organization_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties, value, precise_total_amount_cents FROM events_enriched_queue;

CREATE MATERIALIZED VIEW events_raw_mv TO events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String), `precise_total_amount_cents` Nullable(Decimal(40, 15)), `ingested_at` DateTime64(3) ) AS SELECT organization_id, external_customer_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties, precise_total_amount_cents, ingested_at FROM events_raw_queue;

INSERT INTO schema_migrations (version) VALUES
('20240705085501'),
('20240705084952'),
('20240705080709'),
('20231030163703'),
('20231026124912'),
('20231024084411');

