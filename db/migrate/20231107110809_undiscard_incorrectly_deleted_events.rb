# frozen_string_literal: true

class UndiscardIncorrectlyDeletedEvents < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          WITH discarded_events AS (
            SELECT events.id AS event_id
            FROM events
            INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
            INNER JOIN billable_metrics ON billable_metrics.code = events.code
            WHERE (events.timestamp::timestamp(0) >= '2023-10-01')
              AND events.deleted_at IS NOT NULL
              AND events.deleted_at > billable_metrics.created_at
              AND billable_metrics.deleted_at IS NULL
              AND subscriptions.status IN (0, 1) -- pending and active subscriptions
          )

          UPDATE events
          SET deleted_at = NULL
          FROM discarded_events
          WHERE discarded_events.event_id = events.id
          SQL
        end
      end
    end
  end
end
