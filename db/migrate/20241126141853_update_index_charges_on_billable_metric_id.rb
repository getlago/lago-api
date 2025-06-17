# frozen_string_literal: true

class UpdateIndexChargesOnBillableMetricId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :charges, %i[billable_metric_id], algorithm: :concurrently

    add_index :charges,
      %i[billable_metric_id],
      algorithm: :concurrently,
      where: "deleted_at IS NULL"
  end
end
