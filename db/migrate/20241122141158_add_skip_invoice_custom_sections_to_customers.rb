# frozen_string_literal: true

class AddSkipInvoiceCustomSectionsToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :skip_invoice_custom_sections, :boolean, default: false, null: false
  end
end
