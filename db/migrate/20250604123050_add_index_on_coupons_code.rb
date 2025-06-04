# frozen_string_literal: true

class AddIndexOnCouponsCode < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :coupons, :code, name: "index_coupons_on_code", algorithm: :concurrently
  end
end
