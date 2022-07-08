# frozen_string_literal: true

class AddFileToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :file, :string
  end
end
