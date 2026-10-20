ALTER TABLE default.events_enriched
    ADD INDEX IF NOT EXISTS idx_enriched_at enriched_at TYPE minmax GRANULARITY 1;
ALTER TABLE default.events_enriched
    MATERIALIZE INDEX IF EXISTS idx_enriched_at;
