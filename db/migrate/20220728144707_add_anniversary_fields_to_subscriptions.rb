# frozen_string_literal: true

class AddAnniversaryFieldsToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :billing_time, :integer, null: false, default: 0
    safety_assured do
      rename_column :subscriptions, :anniversary_date, :subscription_date
    end
  end
end
