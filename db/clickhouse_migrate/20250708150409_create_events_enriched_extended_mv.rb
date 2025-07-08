# frozen_string_literal: false

class CreateEventsEnrichedExtendedMv < ActiveRecord::Migration[8.0]
  def change
    sql = <<~SQL
      SELECT
        organization_id,
        external_subscription_id,
        transaction_id,
        toDateTime64(timestamp, 3) AS timestamp,
        code,
        JSONExtract(properties, 'Map(String, String)') AS properties,
        value,
        precise_total_amount_cents,
        subscription_id,
        plan_id,
        COALESCE(charge_id, '') AS charge_id,
        toDateTime64OrNull(charge_updated_at, 3) AS charge_version,
        COALESCE(charge_filter_id, '') AS charge_filter_id,
        toDateTime64OrNull(charge_filter_updated_at, 3) AS charge_filter_version,
        aggregation_type
      FROM events_enriched_extended_queue
    SQL

    create_view :events_enriched_extended_mv, materialized: true, as: sql, to: "events_enriched_extended"
  end
end
