# frozen_string_literal: true

class AddProductEventsRawTransactionIdIndex < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "ALTER TABLE product_events_raw ADD INDEX IF NOT EXISTS idx_product_events_raw_transaction_id transaction_id TYPE bloom_filter(0.01) GRANULARITY 1"
      execute "ALTER TABLE product_events_raw MATERIALIZE INDEX IF EXISTS idx_product_events_raw_transaction_id"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE product_events_raw DROP INDEX IF EXISTS idx_product_events_raw_transaction_id"
    end
  end
end
