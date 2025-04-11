# frozen_string_literal: true

class CreateSubscriptionUsageActivities < ActiveRecord::Migration[7.2]
  def change
    create_table :subscription_usage_activities, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true, index: {unique: true}
      t.boolean :recalculate_current_usage, null: false, default: false
      t.timestamps
    end
  end
end
