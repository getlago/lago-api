# frozen_string_literal: true

class AddSubscriptionRateScheduleCycleToFees < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      add_reference :fees, :subscription_rate_schedule_cycle, type: :uuid, foreign_key: true,
        index: {name: "idx_fees_on_srs_cycle_id"}
    end
  end
end
