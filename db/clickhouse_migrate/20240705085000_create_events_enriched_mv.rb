# frozen_string_literal

class CreateEventsEnrichedMv < ActiveRecord::Migration[7.1]
  def change
    sql = <<-SQL
      SELECT
        organization_id,
        external_subscription_id,
        transaction_id,
        toDateTime64(timestamp) as timestamp,
        code,
        mapSort(JSONExtract(properties, 'Map(String,String)')) as properties,
        ingested_at,
        transaction_id,
        value as value,
        toDecimal128OrZero(value, 26) as numeric_value
      FROM events_enriched_queue
    SQL

    create_view :events_enriched_mv, materialized: true, as: sql, to: 'events_enriched'
  end
end
