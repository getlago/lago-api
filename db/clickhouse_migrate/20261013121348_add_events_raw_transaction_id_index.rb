# frozen_string_literal: true

class AddEventsRawTransactionIdIndex < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "ALTER TABLE events_raw ADD INDEX IF NOT EXISTS idx_events_raw_transaction_id transaction_id TYPE bloom_filter(0.01) GRANULARITY 1"
      execute "ALTER TABLE events_raw MATERIALIZE INDEX IF EXISTS idx_events_raw_transaction_id"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE events_raw DROP INDEX IF EXISTS idx_events_raw_transaction_id"
    end
  end
end
