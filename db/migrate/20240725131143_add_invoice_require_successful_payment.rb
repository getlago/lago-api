# frozen_string_literal: true

class AddInvoiceRequireSuccessfulPayment < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :wallets, :invoice_require_successful_payment, :boolean, default: false, null: false
    add_column :wallet_transactions, :invoice_require_successful_payment, :boolean, default: false, null: false
    add_column :recurring_transaction_rules, :invoice_require_successful_payment, :boolean, default: false, null: false
  end
end
