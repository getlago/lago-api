# frozen_string_literal: true

class CreateProductEventsDeadLetterQueue < ActiveRecord::Migration[8.0]
  # Without a topic the Kafka table would subscribe to nothing. Skip it, and run
  # this migration again once LAGO_KAFKA_PRODUCT_EVENTS_DEAD_LETTER_TOPIC is set.
  def up
    return if ENV["LAGO_KAFKA_PRODUCT_EVENTS_DEAD_LETTER_TOPIC"].blank?

    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_dead_letter_queue (
          event String,
          initial_error_message String,
          error_code String,
          error_message String,
          failed_at String
        ) ENGINE = Kafka
        SETTINGS
          kafka_broker_list = '#{ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]}',
          kafka_topic_list = '#{ENV["LAGO_KAFKA_PRODUCT_EVENTS_DEAD_LETTER_TOPIC"]}',
          kafka_group_name = '#{ENV["LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP"]}',
          kafka_format = 'JSONEachRow'
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_dead_letter_queue"
    end
  end
end
