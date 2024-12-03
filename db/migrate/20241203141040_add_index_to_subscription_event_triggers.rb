# frozen_string_literal: true

class AddIndexToSubscriptionEventTriggers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    add_index :subscription_event_triggers, %i[start_processing_at external_subscription_id organization_id], unique: true, algorithm: :concurrently
    add_index :subscription_event_triggers, %i[external_subscription_id organization_id], unique: true, algorithm: :concurrently, where: 'start_processing_at IS NULL'
  end
end
