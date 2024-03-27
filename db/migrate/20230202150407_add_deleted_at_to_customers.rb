# frozen_string_literal: true

class AddDeletedAtToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :deleted_at, :datetime
    add_index :customers, :deleted_at

    remove_index :customers, %i[external_id organization_id]
    add_index :customers, %i[external_id organization_id], unique: true, where: "deleted_at IS NULL"
  end
end
