# frozen_string_literal: true

class AddContractsCodeIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:contracts, nil, name: :index_contracts_on_organization_id_external_id_code, valid: false)
      remove_index :contracts, name: :index_contracts_on_organization_id_external_id_code, algorithm: :concurrently
    end

    add_index :contracts, [:organization_id, :external_id, :code],
      unique: true,
      name: :index_contracts_on_organization_id_external_id_code,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :contracts, name: :index_contracts_on_organization_id_external_id_code,
      algorithm: :concurrently, if_exists: true
  end
end
