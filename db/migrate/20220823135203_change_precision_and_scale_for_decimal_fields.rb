class ChangePrecisionAndScaleForDecimalFields < ActiveRecord::Migration[7.0]
  def change
    change_column :wallets, :rate_amount, :decimal, precision: 30, scale: 5
    change_column :wallets, :credits_balance, :decimal, precision: 30, scale: 5
    change_column :wallets, :balance, :decimal, precision: 30, scale: 5
    change_column :wallets, :consumed_credits, :decimal, precision: 30, scale: 5
    change_column :wallets, :consumed_amount, :decimal, precision: 30, scale: 5
    change_column :wallet_transactions, :amount, :decimal, precision: 30, scale: 5
    change_column :wallet_transactions, :credit_amount, :decimal, precision: 30, scale: 5
  end
end
