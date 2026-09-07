# frozen_string_literal: true

class ValidateWalletTransactionsPaymentMethodsForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :wallet_transactions, :payment_methods
  end
end
