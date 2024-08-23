# frozen_string_literal: true

class ChangePrecisionAndScaleForDecimalFields < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :wallets, bulk: true do |t|
        t.change :rate_amount, :decimal, precision: 30, scale: 5
        t.change :credits_balance, :decimal, precision: 30, scale: 5
        t.change :balance, :decimal, precision: 30, scale: 5
        t.change :consumed_credits, :decimal, precision: 30, scale: 5
        t.change :consumed_amount, :decimal, precision: 30, scale: 5
      end

      change_table :wallet_transactions, bulk: true do |t|
        t.change :amount, :decimal, precision: 30, scale: 5
        t.change :credit_amount, :decimal, precision: 30, scale: 5
      end
    end
  end

  def down
  end
end
