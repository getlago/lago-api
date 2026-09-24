ALTER TABLE default.events_enriched
    ADD COLUMN IF NOT EXISTS `attribution_labels` Map(String, String);
