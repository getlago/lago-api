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

ClickhouseActiverecord::Schema.define(version: 2023_10_30_163703) do

  # TABLE: events_raw
  # SQL: CREATE TABLE default.events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String) ) ENGINE = MergeTree ORDER BY (organization_id, external_subscription_id, code, timestamp) SETTINGS index_granularity = 8192
  create_table "events_raw", id: false, options: "MergeTree ORDER BY (organization_id, external_subscription_id, code, timestamp) SETTINGS index_granularity = 8192", force: :cascade do |t|
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

  # TABLE: events_raw_mv
  # SQL: CREATE MATERIALIZED VIEW default.events_raw_mv TO default.events_raw ( `organization_id` String, `external_customer_id` String, `external_subscription_id` String, `transaction_id` String, `timestamp` DateTime64(3), `code` String, `properties` Map(String, String) ) AS SELECT organization_id, external_customer_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties FROM default.events_raw_queue
  create_table "events_raw_mv", view: true, materialized: true, id: false, as: "SELECT organization_id, external_customer_id, external_subscription_id, transaction_id, toDateTime64(timestamp, 3) AS timestamp, code, JSONExtract(properties, 'Map(String, String)') AS properties FROM default.events_raw_queue", force: :cascade do |t|
  end

end
