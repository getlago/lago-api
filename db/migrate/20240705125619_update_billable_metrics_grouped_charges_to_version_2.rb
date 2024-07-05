# frozen_string_literal: true

class UpdateBillableMetricsGroupedChargesToVersion2 < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    drop_view :billable_metrics_grouped_charges
    create_view :billable_metrics_grouped_charges, version: 2
  end
end
