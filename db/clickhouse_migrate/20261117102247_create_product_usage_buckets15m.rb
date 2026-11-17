# frozen_string_literal: true

class CreateProductUsageBuckets15m < ActiveRecord::Migration[8.0]
  # usage_buckets_15m for contracts, written by RisingWave from the product events. Keyed by
  # contract, product and product filter rather than subscription and charge.
  #
  # card_effective_date is empty unless the event falls in the day around a change of card
  # version: the pipeline does not know the customer timezone, so it counts such an event once
  # per version that may apply, tagged with the version's effective date, and the reader keeps
  # the one of the billing segment it prices.
  def up
    safety_assured do
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS product_usage_buckets_15m (
            bucket DateTime64(3),
            organization_id String,
            contract_id String,
            customer_id String,
            code String,
            product_id String,
            product_filter_id String,
            card_effective_date String,
            grouped_by String,
            aggregation_type String,
            events_count Int64,
            units Decimal(38, 20),
            precise_total_amount_cents Decimal(38, 15) DEFAULT 0,
            last_event_at DateTime64(3),
            last_ingested_at DateTime64(3),
            is_deleted UInt8 DEFAULT 0,
            ver DateTime64(3) MATERIALIZED now64(3)
        ) ENGINE = ReplacingMergeTree(ver, is_deleted)
        PARTITION BY toYYYYMM(bucket)
        ORDER BY (organization_id, contract_id, product_id, product_filter_id, card_effective_date, grouped_by, bucket)
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS product_usage_buckets_15m"
    end
  end
end
