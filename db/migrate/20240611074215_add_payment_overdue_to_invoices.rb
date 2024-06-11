# frozen_string_literal: true

class AddPaymentOverdueToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :payment_overdue, :boolean, default: false
    add_index :invoices, :payment_overdue

    reversible do |dir|
      dir.up do
        # Set existing invoices as payment_overdue
        execute <<-SQL
          UPDATE invoices
            SET payment_overdue = true
            WHERE status = 1 -- finalized
            AND payment_status != 1 -- not succeeded
            AND payment_dispute_lost_at IS NULL -- not lost dispute
            AND payment_due_date < NOW(); -- due date is in the past
        SQL
      end
    end
  end
end
