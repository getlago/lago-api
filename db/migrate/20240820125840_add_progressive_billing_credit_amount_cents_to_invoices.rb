# frozen_string_literal: true

class AddProgressiveBillingCreditAmountCentsToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :progressive_billing_credit_amount_cents, :bigint, default: 0, null: false
  end
end
