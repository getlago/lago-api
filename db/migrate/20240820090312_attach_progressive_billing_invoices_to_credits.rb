# frozen_string_literal: true

class AttachProgressiveBillingInvoicesToCredits < ActiveRecord::Migration[7.1]
  def change
    add_column :credits, :progressive_billing_invoice_id, :uuid
    safety_assured do
      add_foreign_key :credits, :invoices, column: :progressive_billing_invoice_id
      add_index :credits, :progressive_billing_invoice_id
    end
  end
end
