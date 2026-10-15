# frozen_string_literal: true

class DropCatalogEventsRawMv < ActiveRecord::Migration[8.0]
  # First of five migrations moving catalog_events_raw to product_events_raw, whose queue reads
  # LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC. Views go before their queue, as in
  # 20261008100000_drop_events_enriched_mv.rb: messages wait in the topic meanwhile.
  def up
    safety_assured do
      execute "DROP VIEW IF EXISTS catalog_events_raw_mv"
    end
  end

  def down
    return unless table_exists?(:catalog_events_raw_queue)

    safety_assured do
      execute <<~SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS catalog_events_raw_mv TO catalog_events_raw AS
        SELECT
          organization_id,
          external_customer_id,
          external_contract_id,
          transaction_id,
          toDateTime64(timestamp, 3) AS timestamp,
          code,
          JSONExtract(properties, 'Map(String, String)') AS properties,
          precise_total_amount_cents,
          ingested_at
        FROM catalog_events_raw_queue
      SQL
    end
  end
end
