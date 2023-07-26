# frozen_string_literal: true

class AddPaymentDueDateToInvoice < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :payment_due_date, :date
  end
end
