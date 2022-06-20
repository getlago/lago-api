# frozen_string_literal: true

class AddNumberToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :number, :string, null: false, index: true, default: ''
  end
end
