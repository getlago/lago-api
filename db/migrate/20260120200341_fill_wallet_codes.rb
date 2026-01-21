# frozen_string_literal: true

class FillWalletCodes < ActiveRecord::Migration[8.0]
  def change
    Wallet.udpate_all("code = id)")
  end
end
