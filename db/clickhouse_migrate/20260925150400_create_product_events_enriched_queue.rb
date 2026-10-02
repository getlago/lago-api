# frozen_string_literal: true

class CreateProductEventsEnrichedQueue < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_enriched_queue (
          organization_id String,
          external_contract_id String,
          code String,
          timestamp String,
          transaction_id String,
          properties String,
          value Nullable(String),
          precise_total_amount_cents Nullable(Decimal(40, 15))
        ) ENGINE = Kafka
        SETTINGS
          kafka_broker_list = '#{ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]}',
          kafka_topic_list = '#{ENV["LAGO_KAFKA_PRODUCT_ENRICHED_EVENTS_TOPIC"]}',
          kafka_group_name = '#{ENV["LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP"]}',
          kafka_format = 'JSONEachRow'
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_enriched_queue"
    end
  end
end
