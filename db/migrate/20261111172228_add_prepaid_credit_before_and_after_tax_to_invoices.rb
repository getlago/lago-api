# frozen_string_literal: true

class AddPrepaidCreditBeforeAndAfterTaxToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :prepaid_credit_before_tax_amount_cents, :bigint, null: false, default: 0, if_not_exists: true
    add_column :invoices, :prepaid_credit_after_tax_amount_cents, :bigint, null: false, default: 0, if_not_exists: true
  end
end
