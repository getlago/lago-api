# frozen_string_literal: true

class CreateProductEventsEnrichedMv < ActiveRecord::Migration[8.0]
  # The queue is skipped when the product topic is not configured.
  def up
    return unless table_exists?(:product_events_enriched_queue)

    safety_assured do
      execute <<~SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS product_events_enriched_mv TO product_events_enriched AS
        SELECT
          organization_id,
          external_contract_id,
          transaction_id,
          toDateTime64(timestamp, 3) AS timestamp,
          code,
          JSONExtract(properties, 'Map(String, String)') AS properties,
          value,
          precise_total_amount_cents,
          JSONExtract(attribution_labels, 'Map(String, String)') AS attribution_labels
        FROM product_events_enriched_queue
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP VIEW IF EXISTS product_events_enriched_mv"
    end
  end
end
