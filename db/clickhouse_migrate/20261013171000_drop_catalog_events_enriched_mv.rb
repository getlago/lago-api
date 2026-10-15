# frozen_string_literal: true

class DropCatalogEventsEnrichedMv < ActiveRecord::Migration[8.0]
  # First of five migrations moving catalog_events_enriched to product_events_enriched, whose queue reads
  # LAGO_KAFKA_PRODUCT_ENRICHED_EVENTS_TOPIC. Views go before their queue, as in
  # 20261008100000_drop_events_enriched_mv.rb: messages wait in the topic meanwhile.
  def up
    safety_assured do
      execute "DROP VIEW IF EXISTS catalog_events_enriched_mv"
    end
  end

  def down
    return unless table_exists?(:catalog_events_enriched_queue)

    safety_assured do
      execute <<~SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS catalog_events_enriched_mv TO catalog_events_enriched AS
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
        FROM catalog_events_enriched_queue
      SQL
    end
  end
end
