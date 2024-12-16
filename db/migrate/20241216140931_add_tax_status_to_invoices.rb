# frozen_string_literal: true

class AddTaxStatusToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :tax_status, :integer, null: false, default: 1
  end
end
