# frozen_string_literal: true

class CreateEventsEnrichedQueue < ActiveRecord::Migration[7.1]
  def change
    options = <<-SQL
      Kafka()
      SETTINGS
        kafka_broker_list = '#{ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]}',
        kafka_topic_list = '#{ENV["LAGO_KAFKA_ENRICHED_EVENTS_TOPIC"]}',
        kafka_group_name = '#{ENV["LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP"]}',
        kafka_format = 'JSONEachRow';
    SQL

    create_table :events_enriched_queue, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.string :timestamp, null: false
      t.string :transaction_id, null: false
      t.string :properties, null: false
      t.string :value
      t.string :charge_id, null: false
      t.string :aggregation_type, null: false
      t.string :filters
      t.string :grouped_by
    end
  end
end
