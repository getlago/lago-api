# frozen_string_literal: true

class AddSubscriptionRateScheduleToFees < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      add_reference :fees, :subscription_rate_schedule, type: :uuid, foreign_key: true, index: true
    end
  end
end
