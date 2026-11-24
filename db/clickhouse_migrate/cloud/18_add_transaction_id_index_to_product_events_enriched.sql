ALTER TABLE default.product_events_enriched
    ADD INDEX IF NOT EXISTS idx_product_events_enriched_transaction_id transaction_id TYPE bloom_filter(0.01) GRANULARITY 1;
ALTER TABLE default.product_events_enriched
    MATERIALIZE INDEX IF EXISTS idx_product_events_enriched_transaction_id;
