# frozen_string_literal: false

class CreateEventsRawMv < ActiveRecord::Migration[7.0]
  def change
    sql = <<-SQL
      SELECT
        organization_id,
        external_customer_id,
        external_subscription_id,
        transaction_id,
        timestamp,
        code,
        cast(JSONExtractKeysAndValuesRaw(properties), 'Map(String, String)') as properties
      FROM events_raw_queue
    SQL

    create_view :events_raw_mv, materialized: true, as: sql, to: 'events_raw'
  end
end
