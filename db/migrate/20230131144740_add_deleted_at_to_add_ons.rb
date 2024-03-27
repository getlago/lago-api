# frozen_string_literal: true

class AddDeletedAtToAddOns < ActiveRecord::Migration[7.0]
  def change
    add_column :add_ons, :deleted_at, :datetime
    add_index :add_ons, :deleted_at

    remove_index :add_ons, %i[organization_id code]
    add_index :add_ons, %i[organization_id code], unique: true, where: "deleted_at IS NULL"
  end
end
