# frozen_string_literal: true

class AddCustomersExternalIdOnlyIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def change
    add_index :customers, [:external_id],
      name: "index_customers_on_external_id_only",
      algorithm: :concurrently,
      using: :btree,
      if_not_exists: true,
      where: "deleted_at IS NULL"
  end
end
