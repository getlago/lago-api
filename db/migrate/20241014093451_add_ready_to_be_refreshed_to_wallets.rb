# frozen_string_literal: true

class AddReadyToBeRefreshedToWallets < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :wallets, :ready_to_be_refreshed, :boolean, default: false, null: false
    add_index :wallets, :ready_to_be_refreshed, where: "ready_to_be_refreshed", algorithm: :concurrently
  end
end
