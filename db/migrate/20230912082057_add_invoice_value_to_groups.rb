# frozen_string_literal: true

class AddInvoiceValueToGroups < ActiveRecord::Migration[7.0]
  def change
    add_column :groups, :invoice_value, :string
  end
end
