# frozen_string_literal: true

class AddBillingAnchorDateToSubscriptionRateSchedules < ActiveRecord::Migration[8.0]
  def change
    add_column :subscription_rate_schedules, :billing_anchor_date, :date
  end
end
