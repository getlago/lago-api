# frozen_string_literal: true

class AddIndexOnSubscriptionsPreviousSubscriptionId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :subscriptions, [:previous_subscription_id, :status],
      algorithm: :concurrently,
      if_not_exists: true
  end
end
