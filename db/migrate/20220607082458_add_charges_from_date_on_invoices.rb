# frozen_string_literal: true

class AddChargesFromDateOnInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :charges_from_date, :date
  end
end
