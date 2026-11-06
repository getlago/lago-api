# frozen_string_literal: true

class CreateProductEventsDeadLetter < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_dead_letter (
          organization_id String,
          external_contract_id String,
          code String,
          transaction_id String,
          timestamp DateTime64(3),
          ingested_at DateTime64(3),
          failed_at DateTime64(3),
          event JSON,
          initial_error_message String,
          error_code String,
          error_message String
        ) ENGINE = MergeTree
        ORDER BY (organization_id, external_contract_id, code, transaction_id, timestamp, ingested_at)
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_dead_letter"
    end
  end
end
