# frozen_string_literal: false

# First of three migrations carrying `attribution_labels` from the enriched events topic. The Kafka
# engine does not support ALTER ADD COLUMN, so `events_enriched_queue` is recreated, and the view is
# dropped before and created after it: a Kafka queue builds its consuming pipeline from the views
# attached when it starts, so a queue recreated under the old view would keep running the old query
# for a while and drop the labels of the messages it consumes meanwhile. Without a view the queue
# consumes nothing, and messages wait in the topic until the new view attaches; the recreated queue
# resumes from the committed offsets of the same consumer group.
class DropEventsEnrichedMv < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "DROP VIEW IF EXISTS events_enriched_mv"
    end
  end

  def down
    sql = <<~SQL
      SELECT
        organization_id,
        external_subscription_id,
        transaction_id,
        toDateTime64(timestamp, 3) AS timestamp,
        code,
        JSONExtract(properties, 'Map(String, String)') AS properties,
        value,
        precise_total_amount_cents
      FROM events_enriched_queue
    SQL

    create_view :events_enriched_mv, materialized: true, as: sql, to: "events_enriched", if_not_exists: true
  end
end
