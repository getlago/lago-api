# frozen_string_literal: true

class FixWalletConsumedAmountCurrencyNaming < ActiveRecord::Migration[7.0]
  def change
    rename_column(:wallets, :consumed_amount_currenty, :consumed_amount_currency)
  end
end
