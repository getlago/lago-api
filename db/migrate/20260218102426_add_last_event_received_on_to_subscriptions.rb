# frozen_string_literal: true

class AddLastEventReceivedOnToSubscriptions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :subscriptions, :last_received_event_on, :date
    add_index :subscriptions, :last_received_event_on,
      name: "index_subscriptions_on_last_received_event_on",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
