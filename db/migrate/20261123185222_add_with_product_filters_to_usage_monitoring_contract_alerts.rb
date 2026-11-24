# frozen_string_literal: true

class AddWithProductFiltersToUsageMonitoringContractAlerts < ActiveRecord::Migration[8.1]
  def change
    add_column :usage_monitoring_contract_alerts, :with_product_filters, :boolean, null: false, default: false, if_not_exists: true
  end
end
