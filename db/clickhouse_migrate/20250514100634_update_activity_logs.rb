# frozen_string_literal: true

class UpdateActivityLogs < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      # Enable JSON type support
      execute "SET enable_json_type = 1"

      # Create temporary table with the updated schema
      options = <<-SQL
        ReplacingMergeTree(logged_at)
        PRIMARY KEY (organization_id, activity_type, activity_id, logged_at)
        ORDER BY (organization_id, activity_type, activity_id, logged_at)
      SQL

      create_table :activity_logs_new, id: false, options: do |t|
        t.string :organization_id, null: false
        t.string :user_id
        t.string :api_key_id

        t.string :external_customer_id
        t.string :external_subscription_id
        t.string :billing_entity_id  # Add billing entity id

        t.string :activity_id, null: false
        t.string :activity_type, null: false
        t.enum :activity_source, value: {api: 1, front: 2, system: 3}, null: false
        
        # Change activity_object and activity_object_changes to JSON type with null: false
        t.json :activity_object, null: false, default: {}
        t.json :activity_object_changes, null: false, default: {}

        t.string :resource_id, null: false
        t.string :resource_type, null: false

        t.datetime :logged_at, null: false, precision: 3
        t.datetime :created_at, null: false, precision: 3
      end

      # Copy data from original table to new table
      execute <<-SQL
        INSERT INTO activity_logs_new
        SELECT
          organization_id,
          user_id,
          api_key_id,
          external_customer_id,
          external_subscription_id,
          NULL as billing_entity_id,
          activity_id,
          activity_type,
          activity_source,
          IF(activity_object = '' OR activity_object IS NULL, '{}', activity_object) as activity_object,
          IF(activity_object_changes = '' OR activity_object_changes IS NULL, '{}', activity_object_changes) as activity_object_changes,
          resource_id,
          resource_type,
          logged_at,
          created_at
        FROM activity_logs
      SQL

      # Drop the original table
      drop_table :activity_logs

      # Rename the new table to the original name
      rename_table :activity_logs_new, :activity_logs

      # Update the queue table
      queue_options = <<-SQL
        Kafka()
        SETTINGS
          kafka_broker_list = '#{ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"]}',
          kafka_topic_list = '#{ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"]}',
          kafka_group_name = '#{ENV["LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP"]}',
          kafka_format = 'JSONEachRow'
      SQL

      create_table :activity_logs_queue_new, id: false, options: queue_options do |t|
        t.string :organization_id, null: false
        t.string :user_id
        t.string :api_key_id

        t.string :external_customer_id
        t.string :external_subscription_id
        t.string :billing_entity_id  # Add billing entity id

        t.string :activity_id, null: false
        t.string :activity_type, null: false
        t.enum :activity_source, value: {api: 1, front: 2, system: 3}, null: false
        
        # Change activity_object and activity_object_changes to JSON type with null: false
        t.json :activity_object, null: false, default: {}
        t.json :activity_object_changes, null: false, default: {}

        t.string :resource_id, null: false
        t.string :resource_type, null: false

        t.datetime :logged_at, null: false, precision: 3
        t.datetime :created_at, null: false, precision: 3
      end

      # Drop the original queue table
      drop_table :activity_logs_queue

      # Rename the new queue table to the original name
      rename_table :activity_logs_queue_new, :activity_logs_queue

      # Update the materialized view to include the new field
      sql = <<-SQL
        SELECT
          organization_id,
          user_id,
          api_key_id,
          external_customer_id,
          external_subscription_id,
          billing_entity_id,
          activity_id,
          resource_id,
          resource_type,
          activity_object,
          activity_object_changes,
          activity_type,
          activity_source,
          logged_at,
          created_at
        FROM activity_logs_queue
      SQL

      # Drop and recreate the view
      drop_view :activity_logs_mv
      create_view :activity_logs_mv, materialized: true, as: sql, to: "activity_logs"
    end
  end
end