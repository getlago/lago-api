# frozen_string_literal: true

class AddContractIdIndexesToEntitlements < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # At most one live row per contract and feature (or privilege). Led by contract_id, so they
  # also serve the lookups of a contract's rows. Rows of other owners have no contract_id and stay
  # out of the indexes, which keeps them small on a table of tens of millions of rows.
  INDEXES = {
    idx_unique_feature_per_contract: [:entitlement_entitlements, %i[contract_id entitlement_feature_id]],
    idx_unique_feature_removal_per_contract: [:entitlement_subscription_feature_removals, %i[contract_id entitlement_feature_id]],
    idx_unique_privilege_removal_per_contract: [:entitlement_subscription_feature_removals, %i[contract_id entitlement_privilege_id]]
  }.freeze

  def up
    INDEXES.each do |name, (table, columns)|
      # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
      # would then keep: drop it so that a retry builds the index again.
      if index_exists?(table, nil, name:, valid: false)
        remove_index table, name:, algorithm: :concurrently
      end

      add_index table, columns,
        name:,
        unique: true,
        where: "contract_id IS NOT NULL AND deleted_at IS NULL",
        algorithm: :concurrently,
        if_not_exists: true
    end
  end

  def down
    INDEXES.each do |name, (table, _columns)|
      remove_index table, name:, algorithm: :concurrently, if_exists: true
    end
  end
end
