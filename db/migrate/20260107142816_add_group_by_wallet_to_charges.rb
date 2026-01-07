# frozen_string_literal: true

class AddGroupByWalletToCharges < ActiveRecord::Migration[8.0]
  def change
    add_column :charges, :group_by_wallet, :boolean, default: false, null: false
  end
end
