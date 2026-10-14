ALTER TABLE default.events_raw
    ADD INDEX IF NOT EXISTS idx_events_raw_transaction_id transaction_id TYPE bloom_filter(0.01) GRANULARITY 1;
ALTER TABLE default.events_raw
    MATERIALIZE INDEX IF EXISTS idx_events_raw_transaction_id;
