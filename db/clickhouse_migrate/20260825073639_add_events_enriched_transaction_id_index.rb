# frozen_string_literal: true

class AddEventsEnrichedTransactionIdIndex < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      ALTER TABLE events_enriched
      ADD INDEX IF NOT EXISTS idx_events_enriched_transaction_id transaction_id
      TYPE bloom_filter(0.01) GRANULARITY 1
    SQL
    execute "ALTER TABLE events_enriched MATERIALIZE INDEX IF EXISTS idx_events_enriched_transaction_id"
  end

  def down
    execute "ALTER TABLE events_enriched DROP INDEX IF EXISTS idx_events_enriched_transaction_id"
  end
end
