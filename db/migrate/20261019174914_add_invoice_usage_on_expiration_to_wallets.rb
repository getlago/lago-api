# frozen_string_literal: true

class AddInvoiceUsageOnExpirationToWallets < ActiveRecord::Migration[8.0]
  def change
    add_column :wallets, :invoice_usage_on_expiration, :boolean, default: false, null: false, if_not_exists: true
  end
end
