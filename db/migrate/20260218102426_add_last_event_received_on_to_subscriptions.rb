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
    remove_column :subscriptions, :last_received_event_on
  end

  private

  def backfill_today
    today = Time.zone.today

    Subscription
      .where(
        id: Event
              .where("DATE(timestamp) = ?", today)
              .where(deleted_at: nil)
              .select(:subscription_id)
              .distinct
      )
      .update_all(last_received_event_on: today)
  end
end