# frozen_string_literal: true

class RemoveRedundantContractExternalIdIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :contracts, name: :index_contracts_on_organization_id_and_external_id,
      algorithm: :concurrently, if_exists: true
  end

  def down
    if index_exists?(:contracts, nil, name: :index_contracts_on_organization_id_and_external_id, valid: false)
      remove_index :contracts, name: :index_contracts_on_organization_id_and_external_id, algorithm: :concurrently
    end

    add_index :contracts, [:organization_id, :external_id],
      name: :index_contracts_on_organization_id_and_external_id,
      algorithm: :concurrently, if_not_exists: true
  end
end
