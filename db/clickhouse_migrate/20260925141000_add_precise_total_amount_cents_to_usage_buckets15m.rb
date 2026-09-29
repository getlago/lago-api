# frozen_string_literal: true

class AddPreciseTotalAmountCentsToUsageBuckets15m < ActiveRecord::Migration[8.0]
  # Sum of the bucket's event precise_total_amount_cents, written by the RisingWave sink on sum
  # rows only. Scale 15 like events_enriched, but 38 digits: the sink cannot deliver Decimal256.
  def up
    safety_assured do
      execute <<~SQL
        ALTER TABLE usage_buckets_15m
        ADD COLUMN IF NOT EXISTS precise_total_amount_cents Decimal(38, 15) DEFAULT 0 AFTER units
      SQL
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE usage_buckets_15m DROP COLUMN IF EXISTS precise_total_amount_cents"
    end
  end
end
