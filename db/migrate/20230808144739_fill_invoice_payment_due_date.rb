# frozen_string_literal: true

class FillInvoicePaymentDueDate < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          UPDATE invoices
          SET payment_due_date = issuing_date
          WHERE payment_due_date IS NULL;
          SQL
        end
      end
    end
  end
end
