# frozen_string_literal: true

class AddLastEventReceivedOnToSubscriptions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :subscriptions, :last_received_event_on, :date
    add_index :subscriptions, :last_received_event_on,
      name: "index_subscriptions_on_last_received_event_on",
      algorithm: :concurrently,
      if_not_exists: true

    backfill_today
  end

  def down
    remove_index :subscriptions, name: "index_subscriptions_on_last_received_event_on", if_exists: true
    remove_column :subscriptions, :last_received_event_on # rubocop:disable Lago/NoDropColumnOrTable
  end

  private

  def backfill_today
    today = Date.current

    safety_assured do
      execute <<~SQL
        UPDATE subscriptions
        SET last_received_event_on = '#{today}'
        WHERE id IN (
          SELECT DISTINCT subscription_id
          FROM events
          WHERE DATE(timestamp) >= '#{today - 1.day}'
            AND deleted_at IS NULL
        )
      SQL
    end
  end
end
