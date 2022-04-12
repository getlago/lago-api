class AddPreviousSubscriptionIdToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :previous_subscription_id, :uuid, index: true
  end
end
