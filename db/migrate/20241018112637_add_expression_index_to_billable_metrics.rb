# frozen_string_literal: true

class AddExpressionIndexToBillableMetrics < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    add_index :billable_metrics, [:organization_id, :code, :expression],
      name: 'index_billable_metrics_on_org_id_and_code_and_expr',
      algorithm: :concurrently,
      where: "expression IS NOT NULL AND expression <> ''"
  end
end
