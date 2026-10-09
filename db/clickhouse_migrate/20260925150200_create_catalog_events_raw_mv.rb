# frozen_string_literal: true

class CreateCatalogEventsRawMv < ActiveRecord::Migration[8.0]
  # The queue is skipped when the catalog topic is not configured.
  def up
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

  def down
    safety_assured do
      execute "DROP VIEW IF EXISTS catalog_events_raw_mv"
    end
  end
end
