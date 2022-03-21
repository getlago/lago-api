# frozen_string_literal: true

class RemoveProRataFromBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    remove_column :billable_metrics, :pro_rata
  end
end
