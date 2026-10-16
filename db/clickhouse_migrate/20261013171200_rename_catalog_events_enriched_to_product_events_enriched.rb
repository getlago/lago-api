# frozen_string_literal: true

class RenameCatalogEventsEnrichedToProductEventsEnriched < ActiveRecord::Migration[8.0]
  # Renamed rather than recreated, so rows already ingested stay.
  def up
    return unless table_exists?(:catalog_events_enriched)
    return if table_exists?(:product_events_enriched)

    safety_assured do
      execute "RENAME TABLE catalog_events_enriched TO product_events_enriched"
    end
  end

  def down
    return unless table_exists?(:product_events_enriched)
    return if table_exists?(:catalog_events_enriched)

    safety_assured do
      execute "RENAME TABLE product_events_enriched TO catalog_events_enriched"
    end
  end
end
