# frozen_string_literal: true

class RenameCatalogEventsRawToProductEventsRaw < ActiveRecord::Migration[8.0]
  # Renamed rather than recreated, so rows already ingested stay.
  def up
    return unless table_exists?(:catalog_events_raw)
    return if table_exists?(:product_events_raw)

    safety_assured do
      execute "RENAME TABLE catalog_events_raw TO product_events_raw"
    end
  end

  def down
    return unless table_exists?(:product_events_raw)
    return if table_exists?(:catalog_events_raw)

    safety_assured do
      execute "RENAME TABLE product_events_raw TO catalog_events_raw"
    end
  end
end
