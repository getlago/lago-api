# frozen_string_literal: true

class AddAttributionLabelsToEventsEnriched < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "ALTER TABLE events_enriched ADD COLUMN IF NOT EXISTS attribution_labels Map(String, String)"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE events_enriched DROP COLUMN IF EXISTS attribution_labels"
    end
  end
end
