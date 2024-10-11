# frozen_string_literal: true

class ChangeValidateOnForeignKeyFromWalletTransactionToCreditNote < ActiveRecord::Migration[7.1]
  def change
    validate_foreign_key :wallet_transactions, :credit_notes
  end
end
