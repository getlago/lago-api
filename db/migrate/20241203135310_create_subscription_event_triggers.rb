# frozen_string_literal: true

class CreateSubscriptionEventTriggers < ActiveRecord::Migration[7.1]
  def change
    # rubocop:disable Rails/CreateTableWithTimestamps
    create_table :subscription_event_triggers, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.string :external_subscription_id, null: false
      t.timestamp :start_processing_at
      t.timestamp :created_at, null: false
    end
    # rubocop:enable Rails/CreateTableWithTimestamps
  end
end
