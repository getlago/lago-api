# frozen_string_literal: true

class AddSkipInvoicePdfToBillingEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :billing_entities, :skip_invoice_pdf, :boolean, default: false, null: false
  end
end
