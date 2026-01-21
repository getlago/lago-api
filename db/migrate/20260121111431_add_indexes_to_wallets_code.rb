# frozen_string_literal: true

class AddIndexesToWalletsCode < ActiveRecord::Migration[8.0]
  def change
    add_index :wallets, [:code, :customer_id], unique: true
    change_column_null :wallets, :code, false
  end
end
