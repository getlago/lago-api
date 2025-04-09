# frozen_string_literal: true

class CreateCustomersExportView < ActiveRecord::Migration[7.0]
  def up
    create_view :exports_customers, version: 1
    create_view :exports_billable_metrics, version: 1
    create_view :exports_plans, version: 1

    create_view :customers_export_view, version: 1, materialized: true
    add_index :customers_export_view, :lago_id, unique: true
    add_index :customers_export_view, :external_id, unique: true

    create_view :fees_export_view, version: 1
  end

  def down
    drop_view :exports_billable_metrics, if_exists: true
    drop_view :exports_customers, if_exists: true
    drop_view :exports_plans, if_exists: true

    drop_view :fees_export_view, revert_to_version: 1

    remove_index :customers_export_view, :external_id
    remove_index :customers_export_view, :lago_id
    drop_view :customers_export_view, materialized: true, revert_to_version: 1
  end
end
