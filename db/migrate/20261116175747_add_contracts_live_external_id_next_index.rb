# frozen_string_literal: true

# A draft is live: it holds its external id like a pending or active contract does. The index is
# built under a temporary name, then swapped in under the original one by the next migration. The
# temporary name keeps the `index_contracts_on_live_external_id` prefix that the RecordNotUnique
# rescues match, so a violation in between is still answered as a duplicate external id.
class AddContractsLiveExternalIdNextIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:contracts, nil, name: :index_contracts_on_live_external_id_next, valid: false)
      remove_index :contracts, name: :index_contracts_on_live_external_id_next, algorithm: :concurrently
    end

    add_index :contracts,
      [:organization_id, :external_id, :status],
      unique: true,
      where: "status IN ('draft', 'pending', 'active')",
      name: :index_contracts_on_live_external_id_next,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :contracts, name: :index_contracts_on_live_external_id_next, algorithm: :concurrently, if_exists: true
  end
end
