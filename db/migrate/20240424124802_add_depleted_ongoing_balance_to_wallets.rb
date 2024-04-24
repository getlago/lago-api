# frozen_string_literal: true

class AddDepletedOngoingBalanceToWallets < ActiveRecord::Migration[7.0]
  def change
    add_column :wallets, :depleted_ongoing_balance, :boolean, null: false, default: false
  end
end
