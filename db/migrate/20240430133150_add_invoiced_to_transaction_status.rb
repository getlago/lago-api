# frozen_string_literal: true

class AddInvoicedToTransactionStatus < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        # Set existing wallet transactions as invoiced when transaction_type is outbound.
        execute <<-SQL
          UPDATE wallet_transactions
            SET transaction_status = 3 -- invoiced
            WHERE transaction_type = 1; -- outbound
        SQL
      end
    end
  end
end
