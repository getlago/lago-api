ALTER TABLE default.usage_buckets_15m
    ADD COLUMN IF NOT EXISTS `precise_total_amount_cents` Decimal(38, 15) DEFAULT 0 AFTER `units`;
