CREATE MATERIALIZED VIEW events_dead_letter_mv TO events_dead_letter
(
    `organization_id` String,
    `external_subscription_id` String,
    `code` String,
    `transaction_id` String,
    `timestamp` DateTime,
    `ingested_at` DateTime,
    `failed_at` DateTime,
    `event` JSON,
    `initial_error_message` String,
    `error_code` String,
    `error_message` String
)
AS SELECT
  JSONExtractString(event, 'organization_id') AS organization_id,
  JSONExtractString(event, 'external_subscription_id') AS external_subscription_id,
  JSONExtractString(event, 'code') AS code,
  JSONExtractString(event, 'transaction_id') AS transaction_id,
  toDateTime64(JSONExtractString(event, 'timestamp'), 3) AS timestamp,
  toDateTime64(JSONExtractString(event, 'ingested_at'), 3) AS ingested_at,
  toDateTime64(parseDateTime64BestEffort(failed_at), 3) as failed_at,
  event,
  error_code,
  error_message,
  initial_error_message
FROM events_dead_letter_queue
