# frozen_string_literal: true

class CreateProductEventsDeadLetterMv < ActiveRecord::Migration[8.0]
  # The queue is skipped when the product dead letter topic is not configured.
  def up
    return unless table_exists?(:product_events_dead_letter_queue)

    safety_assured do
      execute <<~SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS product_events_dead_letter_mv TO product_events_dead_letter AS
        SELECT
          JSONExtractString(event, 'organization_id') AS organization_id,
          JSONExtractString(event, 'external_contract_id') AS external_contract_id,
          JSONExtractString(event, 'code') AS code,
          JSONExtractString(event, 'transaction_id') AS transaction_id,
          COALESCE(
            toDateTime64OrNull(JSONExtractString(event, 'timestamp'), 3),
            toDateTime64(
              toFloat64OrNull(JSONExtractString(event, 'timestamp')), 3
            ),
            toDateTime64(JSONExtractString(event, 'ingested_at'), 3)
          ) AS timestamp,
          toDateTime64(JSONExtractString(event, 'ingested_at'), 3) AS ingested_at,
          toDateTime64(parseDateTime64BestEffort(failed_at), 3) AS failed_at,
          event,
          error_code,
          error_message,
          initial_error_message
        FROM product_events_dead_letter_queue
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP VIEW IF EXISTS product_events_dead_letter_mv"
    end
  end
end
