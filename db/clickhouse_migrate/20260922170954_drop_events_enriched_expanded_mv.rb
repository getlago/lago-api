# frozen_string_literal: false

class DropEventsEnrichedExpandedMv < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "DROP VIEW IF EXISTS events_enriched_expanded_mv"
    end
  end

  def down
    sql = <<-SQL
      SELECT
        organization_id,
        external_subscription_id,
        code,
        toDateTime64(timestamp, 3) AS timestamp,
        transaction_id,
        properties,
        value,
        precise_total_amount_cents,
        subscription_id,
        plan_id,
        coalesce(charge_id, '') AS charge_id,
        toDateTime64(parseDateTimeBestEffortOrNull(charge_updated_at), 3) AS charge_version,
        coalesce(charge_filter_id, '') AS charge_filter_id,
        toDateTime64(parseDateTimeBestEffortOrNull(charge_filter_updated_at), 3) AS charge_filter_version,
        aggregation_type,
        coalesce(grouped_by, '{}') AS grouped_by
      FROM events_enriched_expanded_queue;
    SQL

    create_view :events_enriched_expanded_mv, materialized: true, as: sql, to: "events_enriched_expanded"
  end
end
