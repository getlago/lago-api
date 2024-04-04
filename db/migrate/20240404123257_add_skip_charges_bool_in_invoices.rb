# frozen_string_literal: true

class AddSkipChargesBoolInInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :skip_charges, :boolean, default: false, null: false
  end
end
