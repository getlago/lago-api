# frozen_string_literal: true

class RemoveBillablePeriodFromBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    remove_column :billable_metrics, :billable_period
  end
end
