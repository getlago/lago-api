# frozen_string_literal: true

class AddVoidedInvoiceIdToInvoices < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      add_reference :invoices, :voided_invoice, type: :uuid, foreign_key: {to_table: :invoices}, index: true
    end
  end
end
