# frozen_string_literal: false

class CreateEventsEnrichedMvWithAttributionLabels < ActiveRecord::Migration[8.0]
  def up
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
        JSONExtract(attribution_labels, 'Map(String, String)') AS attribution_labels
      FROM events_enriched_queue
    SQL

    create_view :events_enriched_mv, materialized: true, as: sql, to: "events_enriched", if_not_exists: true
  end

  def down
    safety_assured do
      execute "DROP VIEW IF EXISTS events_enriched_mv"
    end
  end
end
