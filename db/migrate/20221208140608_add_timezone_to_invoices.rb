# frozen_string_literal: true

class AddTimezoneToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :timezone, :string, null: false, default: "UTC"
  end
end
