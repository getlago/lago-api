# frozen_string_literal: true

class AddProgressiveBillingTriggerToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :progressive_billing_trigger, :enum, enum_type: :invoice_progressive_billing_trigger, if_not_exists: true
  end
end
