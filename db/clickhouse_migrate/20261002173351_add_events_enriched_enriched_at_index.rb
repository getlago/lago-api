# frozen_string_literal: true

class AddEventsEnrichedEnrichedAtIndex < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "ALTER TABLE events_enriched ADD INDEX IF NOT EXISTS idx_enriched_at enriched_at TYPE minmax GRANULARITY 1"
      execute "ALTER TABLE events_enriched MATERIALIZE INDEX idx_enriched_at"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE events_enriched DROP INDEX IF EXISTS idx_enriched_at"
    end
  end
end
