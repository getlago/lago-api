# frozen_string_literal: true

class UpdateBillableMetricsGroupedChargesToVersion3 < ActiveRecord::Migration[7.1]
  def change
    drop_view :billable_metrics_grouped_charges
    create_view :billable_metrics_grouped_charges, version: 3
  end
end
