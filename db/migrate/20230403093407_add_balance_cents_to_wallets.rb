# frozen_string_literal: true

class AddBalanceCentsToWallets < ActiveRecord::Migration[7.0]
  def change
    change_table :wallets, bulk: true do |t|
      t.bigint :balance_cents
      t.string :balance_currency

      t.bigint :consumed_amount_cents
      t.string :consumed_amount_currenty
    end

    Wallet.find_each do |wallet|
      currency = Money::Currency.new(wallet.attributes["currency"])

      # NOTE: prevent validation issues with deleted customers
      wallet.customer = Customer.with_discarded.find(wallet.customer_id)

      wallet.update!(
        balance_cents: (wallet.attributes["balance"] * currency.subunit_to_unit).to_i,
        balance_currency: currency.iso_code,
        consumed_amount_cents: (wallet.attributes["consumed_amount"] * currency.subunit_to_unit).to_i,
        consumed_amount_currenty: currency.iso_code
      )
    end

    change_column_default :wallets, :balance_cents, from: nil, to: 0
    change_column_null :wallets, :balance_cents, false
    change_column_null :wallets, :balance_currency, false

    change_column_default :wallets, :consumed_amount_cents, from: nil, to: 0
    change_column_null :wallets, :consumed_amount_cents, false
    change_column_null :wallets, :consumed_amount_currenty, false

    reversible do |dir|
      dir.up do
        remove_column :wallets, :balance
        remove_column :wallets, :consumed_amount
        remove_column :wallets, :currency
      end
    end
  end
end
