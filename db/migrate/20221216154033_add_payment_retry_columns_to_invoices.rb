# frozen_string_literal: true

class AddPaymentRetryColumnsToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :payment_attempts, :integer, default: 0, null: false
    add_column :invoices, :ready_for_payment_processing, :boolean, default: true, null: false
  end
end
