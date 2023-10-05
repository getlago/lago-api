# frozen_string_literal: true

class AddInvoiceDisplayNameToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :invoice_display_name, :string
  end
end
