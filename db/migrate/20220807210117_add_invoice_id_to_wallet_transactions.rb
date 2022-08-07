# frozen_string_literal: true

class AddInvoiceIdToWalletTransactions < ActiveRecord::Migration[7.0]
  def change
    add_reference :wallet_transactions, :invoice, type: :uuid, null: true, index: true, foreign_key: true
  end
end
