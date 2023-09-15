# frozen_string_literal: true

class AddInvoiceDisplayNameToGroupProperties < ActiveRecord::Migration[7.0]
  def up
    remove_column :groups, :invoice_value
    add_column :group_properties, :invoice_display_name, :string
  end

  def down
    add_column :groups, :invoice_value, :string
    remove_column :group_properties, :invoice_display_name
  end
end
