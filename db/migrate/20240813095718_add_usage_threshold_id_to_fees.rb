# frozen_String_literal: true

class AddUsageThresholdIdToFees < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      add_reference :fees, :usage_threshold, type: :uuid, foreign_key: true, index: true
    end
  end
end
