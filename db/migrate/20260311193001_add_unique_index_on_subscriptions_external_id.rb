# frozen_string_literal: true

class AddUniqueIndexOnSubscriptionsExternalId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      # Cleanup duplicates in batches to avoid locking the entire table for a long time
      loop do
        result = execute(<<~SQL)
          WITH
            ranked AS (
              SELECT id,
                ROW_NUMBER() OVER (
                  PARTITION BY organization_id, external_id
                  ORDER BY started_at DESC NULLS LAST, created_at DESC
                ) AS rn
              FROM subscriptions
              WHERE status = 1
            ),
            duplicates AS (
              SELECT id FROM ranked WHERE rn > 1 LIMIT 1000
            )
          UPDATE subscriptions
          SET status = 2, terminated_at = NOW()
          FROM duplicates
          WHERE subscriptions.id = duplicates.id
        SQL
        break if result.cmd_tuples.zero?
      end

      add_index :subscriptions, [:organization_id, :external_id],
        unique: true,
        where: "status = 1",
        name: "index_subscriptions_by_external_id",
        algorithm: :concurrently
    end
  end

  def down
    safety_assured do
      remove_index :subscriptions,
        name: "index_subscriptions_by_external_id",
        algorithm: :concurrently,
        if_exists: true
    end
  end
end
