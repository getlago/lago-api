# frozen_string_literal: true

class CreateProductEventsRaw < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_raw (
          organization_id String,
          external_customer_id String,
          external_contract_id String,
          transaction_id String,
          timestamp DateTime64(3),
          code String,
          properties Map(String, String),
          precise_total_amount_cents Nullable(Decimal(40, 15)),
          ingested_at DateTime64(3)
        ) ENGINE = MergeTree
        ORDER BY (organization_id, external_contract_id, code, transaction_id, timestamp)
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_raw"
    end
  end
end
