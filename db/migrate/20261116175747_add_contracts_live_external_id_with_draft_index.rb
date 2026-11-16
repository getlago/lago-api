# frozen_string_literal: true

# A draft is live: it holds its external id like a pending or active contract does. The name
# keeps the `index_contracts_on_live_external_id` prefix that the RecordNotUnique rescues match.
class AddContractsLiveExternalIdWithDraftIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:contracts, nil, name: :index_contracts_on_live_external_id_with_draft, valid: false)
      remove_index :contracts, name: :index_contracts_on_live_external_id_with_draft, algorithm: :concurrently
    end

    add_index :contracts,
      [:organization_id, :external_id, :status],
      unique: true,
      where: "status IN ('draft', 'pending', 'active')",
      name: :index_contracts_on_live_external_id_with_draft,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :contracts, name: :index_contracts_on_live_external_id_with_draft, algorithm: :concurrently, if_exists: true
  end
end
