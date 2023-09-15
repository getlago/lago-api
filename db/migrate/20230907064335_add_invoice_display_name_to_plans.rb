# frozen_string_literal: true

class AddInvoiceDisplayNameToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :invoice_display_name, :string
  end
end
