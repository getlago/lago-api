# frozen_string_literal: true

class DeduplicateEventsTransactionId < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          WITH duplicated_transaction_id AS (
            SELECT events.id AS event_id
            FROM events
              INNER JOIN
              (
                SELECT
                  organization_id,
                  transaction_id,
                  external_subscription_id
                FROM events
                GROUP BY
                  organization_id,
                  transaction_id,
                  external_subscription_id
                HAVING COUNT(id) > 1
              ) AS duplicated_transactions
              ON duplicated_transactions.organization_id = events.organization_id
                AND duplicated_transactions.transaction_id = events.transaction_id
                AND duplicated_transactions.external_subscription_id = events.external_subscription_id
          )

          UPDATE events
          SET transaction_id = events.transaction_id || '_' || events.id
          FROM duplicated_transaction_id
          WHERE duplicated_transaction_id.event_id = events.id
          SQL
        end
      end
    end
  end
end
