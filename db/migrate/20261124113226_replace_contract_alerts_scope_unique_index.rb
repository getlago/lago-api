# frozen_string_literal: true

# A product scope counts either the product's own fees or its filters' fees too, so each value of
# with_product_filters is its own scope: one alert per type and scope, with the flag in the key.
class ReplaceContractAlertsScopeUniqueIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  SCOPE_COLUMNS = %i[organization_id contract_external_id alert_type product_id product_filter_id].freeze

  def up
    add_scope_index(:idx_contract_alerts_scope_with_filters_unique, [*SCOPE_COLUMNS, :with_product_filters])
    remove_index :usage_monitoring_contract_alerts, name: :idx_contract_alerts_scope_unique, algorithm: :concurrently, if_exists: true
  end

  def down
    add_scope_index(:idx_contract_alerts_scope_unique, SCOPE_COLUMNS)
    remove_index :usage_monitoring_contract_alerts, name: :idx_contract_alerts_scope_with_filters_unique, algorithm: :concurrently, if_exists: true
  end

  private

  def add_scope_index(name, columns)
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists` would then keep:
    # drop it so that a retry builds the index again.
    if index_exists?(:usage_monitoring_contract_alerts, nil, name:, valid: false)
      remove_index :usage_monitoring_contract_alerts, name:, algorithm: :concurrently
    end

    add_index :usage_monitoring_contract_alerts, columns,
      unique: true,
      nulls_not_distinct: true,
      where: "deleted_at IS NULL",
      name:,
      algorithm: :concurrently,
      if_not_exists: true
  end
end
