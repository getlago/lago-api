# frozen_string_literal: true

class AddInvoiceDisplayNameToAddOns < ActiveRecord::Migration[7.0]
  def change
    add_column :add_ons, :invoice_display_name, :string
  end
end
