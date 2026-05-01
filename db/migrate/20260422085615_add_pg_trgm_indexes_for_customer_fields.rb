# frozen_string_literal: true

class AddPgTrgmIndexesForCustomerFields < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    enable_extension "pg_trgm"

    add_index :customers, :name, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently
    add_index :customers, :email, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently
    add_index :customers, :firstname, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently
    add_index :customers, :lastname, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently
    add_index :customers, :legal_name, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently
    add_index :customers, :external_id, using: :gin, opclass: :gin_trgm_ops, where: "deleted_at IS NULL", algorithm: :concurrently, name: "index_customers_on_gin_external_id"
  end
end
