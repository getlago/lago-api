# frozen_string_literal: false

class CreateProductEventsEnrichedMv < ActiveRecord::Migration[8.0]
  def change
    sql = <<~SQL
      SELECT
        organization_id,
        external_subscription_id,
        transaction_id,
        toDateTime64(timestamp, 3) AS timestamp,
        code,
        JSONExtract(properties, 'Map(String, String)') AS properties,
        value,
        precise_total_amount_cents
      FROM product_events_enriched_queue
    SQL

    create_view :product_events_enriched_mv, materialized: true, as: sql, to: "product_events_enriched"
  end
end
