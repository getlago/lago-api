# frozen_string_literal: true

class AddDeletedAtToCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :deleted_at, :datetime
    add_index :coupons, :deleted_at

    remove_index :coupons, %i[organization_id code]
    add_index :coupons, %i[organization_id code], unique: true, where: "deleted_at IS NULL"
  end
end
