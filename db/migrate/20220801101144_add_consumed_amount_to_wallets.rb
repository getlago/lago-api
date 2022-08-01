# frozen_string_literal: true

class AddConsumedAmountToWallets < ActiveRecord::Migration[7.0]
  def change
    add_column :wallets, :consumed_amount, :decimal, default: 0, precision: 5
  end
end
