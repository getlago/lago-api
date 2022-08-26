class RemoveInvoiceFromWalletTransaction < ActiveRecord::Migration[7.0]
  def change
    remove_reference :wallet_transactions, :invoice, index: true, foreign_key: true
  end
end
