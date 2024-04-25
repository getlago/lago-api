# frozen_string_literal: true

class AddTransactionStatusToWalletTransactions < ActiveRecord::Migration[7.0]
  def change
    add_column :wallet_transactions, :transaction_status, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        # Set existing wallet transactions as granted if no invoices linked and status is settled.
        execute <<-SQL
          UPDATE wallet_transactions
            SET transaction_status = 1 -- granted
            WHERE invoice_id IS NULL
            AND status = 1; -- settled
        SQL
      end
    end
  end
end
