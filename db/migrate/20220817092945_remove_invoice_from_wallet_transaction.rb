# frozen_string_literal: true

class RemoveInvoiceFromWalletTransaction < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      remove_reference :wallet_transactions, :invoice, index: true, foreign_key: true
    end
  end
end
