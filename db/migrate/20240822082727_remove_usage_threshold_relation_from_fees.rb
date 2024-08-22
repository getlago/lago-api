# frozen_string_literal: true

class RemoveUsageThresholdRelationFromFees < ActiveRecord::Migration[7.1]
  def up
    remove_column :fees, :usage_threshold_id
  end

  def down
  end
end
