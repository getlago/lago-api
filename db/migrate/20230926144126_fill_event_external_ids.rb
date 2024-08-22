# frozen_string_literal: true

class FillEventExternalIds < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          WITH events_external_ids AS (
            SELECT
              events.id AS event_id,
              customers.external_id AS external_customer_id,
              subscriptions.external_id AS external_subscription_id
            FROM events
              INNER JOIN customers ON customers.id = events.customer_id
              INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
            WHERE events.external_customer_id IS NULL
              AND events.external_subscription_id IS NULL
          )

          UPDATE events
          SET
            external_customer_id = events_external_ids.external_customer_id,
            external_subscription_id = events_external_ids.external_subscription_id
          FROM events_external_ids
          WHERE events_external_ids.event_id = events.id
          SQL
        end
      end
    end
  end
end
