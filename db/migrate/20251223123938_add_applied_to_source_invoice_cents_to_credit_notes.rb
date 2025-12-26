# frozen_string_literal: true

class AddAppliedToSourceInvoiceCentsToCreditNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :credit_notes, :applied_to_source_invoice_amount_cents, :bigint, default: 0, null: false
    add_column :credit_notes, :applied_to_source_invoice_amount_currency, :string
  end
end
