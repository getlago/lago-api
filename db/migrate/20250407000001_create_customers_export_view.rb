# frozen_string_literal: true

class CreateCustomersExportView < ActiveRecord::Migration[7.0]
  def up
    create_view :exports_customers, version: 1
    create_view :exports_billable_metrics, version: 1
    create_view :exports_plans, version: 1
  end

  def down
    drop_view :exports_billable_metrics, if_exists: true
    drop_view :exports_customers, if_exists: true
    drop_view :exports_plans, if_exists: true
  end
end
