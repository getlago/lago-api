# frozen_string_literal: true

class CreateProductEventsRawQueue < ActiveRecord::Migration[8.0]
  # Without a topic the Kafka table would subscribe to nothing. Skip it, and run
  # this migration again once LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC is set.
  def up
    return if ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"].blank?

    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_raw_queue (
          organization_id String,
          external_customer_id String,
          external_contract_id String,
          transaction_id String,
          timestamp String,
          code String,
          properties String,
          precise_total_amount_cents Nullable(Decimal(40, 15)),
          ingested_at DateTime64(3)
        ) ENGINE = Kafka
        SETTINGS
          kafka_broker_list = '#{ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]}',
          kafka_topic_list = '#{ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"]}',
          kafka_group_name = '#{ENV["LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP"]}',
          kafka_format = 'JSONEachRow'
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_raw_queue"
    end
  end
end
