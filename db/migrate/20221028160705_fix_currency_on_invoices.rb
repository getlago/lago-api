# frozen_string_literal: true

class FixCurrencyOnInvoices < ActiveRecord::Migration[7.0]
  def up
    update_query = <<~SQL
      UPDATE fees as f
      SET
        amount_currency = invoices.amount_currency,
        vat_amount_currency = invoices.amount_currency
      FROM invoices
      WHERE f.invoice_id = invoices.id
        AND f.amount_currency IS NULL
        OR f.vat_amount_currency IS NULL
    SQL

    safety_assured { execute(update_query) }
  end
end
