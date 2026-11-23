# frozen_string_literal: true

# Replaces the live external id index with the one that also covers drafts, under the original
# name. Renaming an index takes a SHARE UPDATE EXCLUSIVE lock, which blocks neither reads nor writes.
class SwapContractsLiveExternalIdIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Without the temporary index the swap already happened: removing the original name again
    # would drop the new index.
    return unless index_exists?(:contracts, nil, name: :index_contracts_on_live_external_id_next)

    remove_index :contracts, name: :index_contracts_on_live_external_id, algorithm: :concurrently, if_exists: true
    rename_index :contracts, :index_contracts_on_live_external_id_next, :index_contracts_on_live_external_id
  end

  def down
    unless index_exists?(:contracts, nil, name: :index_contracts_on_live_external_id_next)
      rename_index :contracts, :index_contracts_on_live_external_id, :index_contracts_on_live_external_id_next
    end

    if index_exists?(:contracts, nil, name: :index_contracts_on_live_external_id, valid: false)
      remove_index :contracts, name: :index_contracts_on_live_external_id, algorithm: :concurrently
    end

    add_index :contracts,
      [:organization_id, :external_id, :status],
      unique: true,
      where: "status IN ('pending', 'active')",
      name: :index_contracts_on_live_external_id,
      algorithm: :concurrently,
      if_not_exists: true
  end
end
