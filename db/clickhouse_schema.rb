# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# *****:schema:load`. When creating a new database, `rails *****:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ClickhouseActiverecord::Schema.define(version: 2024_07_09_135535) do

  # TABLE: events_count_agg
  # SQL: CREATE TABLE default.events_count_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `value` Nullable(Decimal(26, 0)), `timestamp` DateTime64(3), `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) ENGINE = SummingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192
  create_table "events_count_agg", id: false, options: "SummingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_subscription_id", null: false
    t.string "code", null: false
    t.string "charge_id", null: false
    t.decimal "value", precision: 26
    t.datetime "timestamp", precision: 3, null: false
    t.map "filters", key_type: "string", value_type: "Array(String)", null: false
    t.map "grouped_by", key_type: "string", value_type: "string", null: false
  end

  # TABLE: events_enriched
  # SQL: CREATE TABLE default.events_enriched ( `organization_id` String, `external_subscription_id` String, `code` String, `timestamp` DateTime64(3), `transaction_id` String, `properties` Map(String, String), `value` Nullable(String), `charge_id` String, `aggregation_type` Nullable(String), `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) ENGINE = ReplacingMergeTree ORDER BY (organization_id, external_subscription_id, code, charge_id, transaction_id) SETTINGS index_granularity = 8192
  create_table "events_enriched", id: false, options: "ReplacingMergeTree ORDER BY (organization_id, external_subscription_id, code, charge_id, transaction_id) SETTINGS index_granularity = 8192", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_subscription_id", null: false
    t.string "code", null: false
    t.datetime "timestamp", precision: 3, null: false
    t.string "transaction_id", null: false
    t.map "properties", key_type: "string", value_type: "string", null: false
    t.string "value"
    t.string "charge_id", null: false
    t.string "aggregation_type"
    t.map "filters", key_type: "string", value_type: "Array(String)", null: false
    t.map "grouped_by", key_type: "string", value_type: "string", null: false
  end

  # TABLE: events_enriched_queue
  # SQL: CREATE TABLE default.events_enriched_queue ( `organization_id` String, `external_subscription_id` String, `code` String, `timestamp` String, `transaction_id` String, `properties` String, `value` Nullable(String), `charge_id` String, `aggregation_type` String, `filters` Nullable(String), `grouped_by` Nullable(String) ) ENGINE = Kafka SETTINGS kafka_broker_list = '*****', kafka_topic_list = '', kafka_group_name = '*****', kafka_format = 'JSONEachRow'
  create_table "events_enriched_queue", id: false, options: "Kafka SETTINGS kafka_broker_list = '*****', kafka_topic_list = '', kafka_group_name = '*****', kafka_format = 'JSONEachRow'", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_subscription_id", null: false
    t.string "code", null: false
    t.string "timestamp", null: false
    t.string "transaction_id", null: false
    t.string "properties", null: false
    t.string "value"
    t.string "charge_id", null: false
    t.string "aggregation_type", null: false
    t.string "filters"
    t.string "grouped_by"
  end

  # TABLE: events_max_agg
  # SQL: CREATE TABLE default.events_max_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `timestamp` DateTime64(3), `filters` Map(String, Array(String)), `grouped_by` Map(String, String), `value` AggregateFunction(max, Decimal(38, 26)) ) ENGINE = AggregatingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192
  create_table "events_max_agg", id: false, options: "AggregatingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_subscription_id", null: false
    t.string "code", null: false
    t.string "charge_id", null: false
    t.datetime "timestamp", precision: 3, null: false
    t.map "filters", key_type: "string", value_type: "Array(String)", null: false
    t.map "grouped_by", key_type: "string", value_type: "string", null: false
    t.decimal "value", precision: 38, scale: 26, null: false
  end

  # TABLE: events_raw
  # SQL: CREATE TABLE default.events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String) ) ENGINE = MergeTree ORDER BY (organization_id, external_subscription_id, code, transaction_id, timestamp) SETTINGS index_granularity = 8192
  create_table "events_raw", id: false, options: "MergeTree ORDER BY (organization_id, external_subscription_id, code, transaction_id, timestamp) SETTINGS index_granularity = 8192", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_customer_id", null: false
    t.string "external_subscription_id", null: false
    t.string "transaction_id", null: false
    t.datetime "timestamp", precision: 3, null: false
    t.string "code", null: false
    t.map "properties", key_type: "string", value_type: "string", null: false
  end

  # TABLE: events_raw_queue
  # SQL: CREATE TABLE default.events_raw_queue ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` String, `code` String, `properties` String ) ENGINE = Kafka SETTINGS kafka_broker_list = '*****', kafka_topic_list = '*****', kafka_group_name = '*****', kafka_format = 'JSONEachRow'
  create_table "events_raw_queue", id: false, options: "Kafka SETTINGS kafka_broker_list = '*****', kafka_topic_list = '*****', kafka_group_name = '*****', kafka_format = 'JSONEachRow'", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_customer_id", null: false
    t.string "external_subscription_id", null: false
    t.string "transaction_id", null: false
    t.string "timestamp", null: false
    t.string "code", null: false
    t.string "properties", null: false
  end

  # TABLE: events_sum_agg
  # SQL: CREATE TABLE default.events_sum_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `value` Nullable(Decimal(26, 0)), `timestamp` DateTime64(3), `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) ENGINE = SummingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192
  create_table "events_sum_agg", id: false, options: "SummingMergeTree PRIMARY KEY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) ORDER BY (organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by) SETTINGS index_granularity = 8192", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "external_subscription_id", null: false
    t.string "code", null: false
    t.string "charge_id", null: false
    t.decimal "value", precision: 26
    t.datetime "timestamp", precision: 3, null: false
    t.map "filters", key_type: "string", value_type: "Array(String)", null: false
    t.map "grouped_by", key_type: "string", value_type: "string", null: false
  end

  # TABLE: events_sum_agg_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_sum_agg_mv TO default.events_sum_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `value` Nullable(Decimal(38, 26)), `timestamp` DateTime, `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) AS SELECT organization_id, external_subscription_id, code, charge_id, sum(toDecimal128(value, 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'sum_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by
  create_table "events_sum_agg_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_subscription_id, code, charge_id, sum(toDecimal128(value, 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'sum_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by", force: :cascade do |t|
  end

  # TABLE: events_raw_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_raw_mv TO default.events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String) ) AS SELECT organization_id, external_customer_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties FROM default.events_raw_queue
  create_table "events_raw_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_customer_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties FROM default.events_raw_queue", force: :cascade do |t|
  end

  # TABLE: events_max_agg_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_max_agg_mv TO default.events_max_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `value` AggregateFunction(max, Decimal(38, 26)), `timestamp` DateTime, `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) AS SELECT organization_id, external_subscription_id, code, charge_id, maxState(toDecimal128(coalesce(value, '0'), 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'max_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by
  create_table "events_max_agg_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_subscription_id, code, charge_id, maxState(toDecimal128(coalesce(value, '0'), 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'max_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by", force: :cascade do |t|
  end

  # TABLE: events_enriched_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_enriched_mv TO default.events_enriched ( `organization_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String), `value` Nullable(String), `charge_id` String, `aggregation_type` String, `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) AS SELECT organization_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties, value, charge_id, aggregation_type, JSONExtract(coalesce(filters, '{}'), 'Map(String, Array(String))') AS filters, JSONExtract(coalesce(grouped_by, '{}'), 'Map(String, String)') AS grouped_by FROM default.events_enriched_queue
  create_table "events_enriched_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties, value, charge_id, aggregation_type, JSONExtract(coalesce(filters, '{}'), 'Map(String, Array(String))') AS filters, JSONExtract(coalesce(grouped_by, '{}'), 'Map(String, String)') AS grouped_by FROM default.events_enriched_queue", force: :cascade do |t|
  end

  # TABLE: events_count_agg_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_count_agg_mv TO default.events_count_agg ( `organization_id` String, `external_subscription_id` String, `code` String, `charge_id` String, `value` Nullable(Decimal(38, 26)), `timestamp` DateTime, `filters` Map(String, Array(String)), `grouped_by` Map(String, String) ) AS SELECT organization_id, external_subscription_id, code, charge_id, sum(toDecimal128(value, 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'count_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by
  create_table "events_count_agg_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_subscription_id, code, charge_id, sum(toDecimal128(value, 26)) AS value, toStartOfHour(timestamp) AS timestamp, filters, grouped_by FROM default.events_enriched WHERE aggregation_type = 'count_agg' GROUP BY organization_id, external_subscription_id, code, charge_id, timestamp, filters, grouped_by", force: :cascade do |t|
  end

end
