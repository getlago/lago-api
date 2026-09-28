# frozen_string_literal: true

class CreateProductEventsEnriched < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_events_enriched (
          organization_id String,
          external_contract_id String,
          code String,
          timestamp DateTime64(3),
          transaction_id String,
          properties Map(String, String),
          sorted_properties Map(String, String) DEFAULT mapSort(properties),
          value Nullable(String),
          decimal_value Nullable(Decimal(38, 26)) DEFAULT toDecimal128OrZero(value, 26),
          enriched_at DateTime64(3) DEFAULT now64(3),
          precise_total_amount_cents Nullable(Decimal(40, 15)),
          attribution_labels Map(String, String)
        ) ENGINE = ReplacingMergeTree(timestamp)
        PRIMARY KEY (organization_id, code, external_contract_id, toDate(timestamp))
        ORDER BY (organization_id, code, external_contract_id, toDate(timestamp), timestamp, transaction_id)
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_events_enriched"
    end
  end
end
