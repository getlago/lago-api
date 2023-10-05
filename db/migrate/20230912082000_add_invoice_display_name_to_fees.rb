# frozen_string_literal: true

class AddInvoiceDisplayNameToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :invoice_display_name, :string
  end
end
