# frozen_string_literal: true

class AddProductEventsEnrichedTransactionIdIndex < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "ALTER TABLE product_events_enriched ADD INDEX IF NOT EXISTS idx_product_events_enriched_transaction_id transaction_id TYPE bloom_filter(0.01) GRANULARITY 1"
      execute "ALTER TABLE product_events_enriched MATERIALIZE INDEX IF EXISTS idx_product_events_enriched_transaction_id"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE product_events_enriched DROP INDEX IF EXISTS idx_product_events_enriched_transaction_id"
    end
  end
end
