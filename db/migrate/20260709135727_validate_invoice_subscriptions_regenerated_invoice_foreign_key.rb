# frozen_string_literal: true

class ValidateInvoiceSubscriptionsRegeneratedInvoiceForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # invoice_subscriptions has two foreign keys to invoices; target the NOT VALID one by column.
    validate_foreign_key :invoice_subscriptions, column: :regenerated_invoice_id
  end
end
