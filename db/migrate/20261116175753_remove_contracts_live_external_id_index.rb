# frozen_string_literal: true

# Superseded by index_contracts_on_live_external_id_with_draft, which covers drafts too.
class RemoveContractsLiveExternalIdIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :contracts, name: :index_contracts_on_live_external_id, algorithm: :concurrently, if_exists: true
  end

  def down
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
