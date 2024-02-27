# frozen_string_literal: true

class AddInvoiceDisplayNameToChargeFilters < ActiveRecord::Migration[7.0]
  def change
    add_column :charge_filters, :invoice_display_name, :string
  end
end
