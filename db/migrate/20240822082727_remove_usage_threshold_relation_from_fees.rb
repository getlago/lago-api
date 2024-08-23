# frozen_string_literal: true

class RemoveUsageThresholdRelationFromFees < ActiveRecord::Migration[7.1]
  def up
    safety_assured do
      remove_column :fees, :usage_threshold_id
    end
  end

  def down
  end
end
