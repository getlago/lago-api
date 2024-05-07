# frozen_string_literal: true

class AddFiltersMissingIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :charge_filters, :charge_id, where: 'deleted_at IS NULL', name: 'index_active_charge_filters'
    add_index :charge_filter_values,
      :charge_filter_id,
      where: 'deleted_at IS NULL',
      name: 'index_active_charge_filter_values'
    add_index :billable_metric_filters,
      :billable_metric_id,
      where: 'deleted_at IS NULL',
      name: 'index_active_metric_filters'
  end
end
