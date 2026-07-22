# frozen_string_literal: true

class AddOldestEventIngestedAtToSubscriptionActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :usage_monitoring_subscription_activities, :oldest_event_ingested_at, :datetime
  end
end
