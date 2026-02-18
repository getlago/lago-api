# frozen_string_literal: true

class AddRecalculateDailyUsageToSubscriptions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :subscriptions, :renew_daily_usage, :boolean, default: false, null: false
    add_index :subscriptions, :renew_daily_usage,
      where: "renew_daily_usage = true",
      name: "index_subscriptions_on_renew_daily_usage_true",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
