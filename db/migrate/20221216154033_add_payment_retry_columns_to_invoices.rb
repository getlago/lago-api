# frozen_string_literal: true

class AddPaymentRetryColumnsToInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.integer :payment_attempts, default: 0, null: false
        t.boolean :ready_for_payment_processing, default: true, null: false
      end
    end
  end
end
