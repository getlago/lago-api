# frozen_string_literal: true

class CreateEventsRawQueue < ActiveRecord::Migration[7.0]
  def change
    options = <<-SQL
    Kafka()
    SETTINGS
      kafka_broker_list = '#{ENV['LAGO_KAFKA_BOOTSTRAP_SERVERS']}',
      kafka_topic_list = '#{ENV['LAGO_KAFKA_RAW_EVENTS_TOPIC']}',
      kafka_group_name = 'clickhouse',
      kafka_format = 'JSONEachRow'
    SQL

    create_table :events_raw_queue, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :external_customer_id, null: false
      t.string :external_subscription_id, null: false
      t.string :transaction_id, null: false
      t.datetime :timestamp, null: false
      t.string :code, null: false
      t.string :properties, null: false
    end
  end
end
