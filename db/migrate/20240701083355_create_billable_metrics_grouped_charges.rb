# frozen_string_literal: true

class CreateBillableMetricsGroupedCharges < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_view :billable_metrics_grouped_charges
  end
end
