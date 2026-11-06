# frozen_string_literal: true

class AddTaxesCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:taxes, nil, name: :index_taxes_by_cursor, valid: false)
      remove_index :taxes, name: :index_taxes_by_cursor, algorithm: :concurrently
    end

    add_index :taxes,
      [:organization_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      where: "deleted_at IS NULL",
      name: :index_taxes_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :taxes, name: :index_taxes_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
