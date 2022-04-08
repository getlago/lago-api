# frozen_string_literal: true

class AddAmountsToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :amount_cents, :bigint, null: false, default: 0
    add_column :invoices, :amount_currency, :string

    add_column :invoices, :vat_amount_cents, :bigint, null: false, default: 0
    add_column :invoices, :vat_amount_currency, :string

    add_column :invoices, :total_amount_cents, :bigint, null: false, default: 0
    add_column :invoices, :total_amount_currency, :string
  end
end
