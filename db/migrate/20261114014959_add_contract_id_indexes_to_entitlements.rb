# frozen_string_literal: true

class AddContractIdIndexesToEntitlements < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEXES = {
    entitlement_entitlements: :index_entitlement_entitlements_on_contract_id,
    entitlement_subscription_feature_removals: :index_entitlement_removals_on_contract_id
  }.freeze

  def up
    INDEXES.each do |table, name|
      # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
      # would then keep: drop it so that a retry builds the index again.
      if index_exists?(table, nil, name:, valid: false)
        remove_index table, name:, algorithm: :concurrently
      end

      add_index table, :contract_id, name:, algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    INDEXES.each do |table, name|
      remove_index table, name:, algorithm: :concurrently, if_exists: true
    end
  end
end
