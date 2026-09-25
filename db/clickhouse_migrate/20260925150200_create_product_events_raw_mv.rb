# frozen_string_literal: false

class CreateProductEventsRawMv < ActiveRecord::Migration[8.0]
  def change
    sql = <<~SQL
      SELECT
        organization_id,
        external_customer_id,
        external_subscription_id,
        transaction_id,
        toDateTime64(timestamp, 3) AS timestamp,
        code,
        JSONExtract(properties, 'Map(String, String)') AS properties,
        precise_total_amount_cents,
        ingested_at
      FROM product_events_raw_queue
    SQL

    create_view :product_events_raw_mv, materialized: true, as: sql, to: "product_events_raw"
  end
end
