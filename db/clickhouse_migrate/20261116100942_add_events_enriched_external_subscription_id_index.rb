# frozen_string_literal: true

class AddEventsEnrichedExternalSubscriptionIdIndex < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "ALTER TABLE events_enriched ADD INDEX IF NOT EXISTS idx_external_subscription_id external_subscription_id TYPE bloom_filter(0.01) GRANULARITY 1"
      execute "ALTER TABLE events_enriched MATERIALIZE INDEX IF EXISTS idx_external_subscription_id"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE events_enriched DROP INDEX IF EXISTS idx_external_subscription_id"
    end
  end
end
