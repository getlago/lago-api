ALTER TABLE default.product_events_enriched
    ADD INDEX IF NOT EXISTS idx_product_events_enriched_enriched_at enriched_at TYPE minmax GRANULARITY 1;
ALTER TABLE default.product_events_enriched
    MATERIALIZE INDEX IF EXISTS idx_product_events_enriched_enriched_at;
