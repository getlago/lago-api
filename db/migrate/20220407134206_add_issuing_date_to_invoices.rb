# frozen_string_literal: true

class AddIssuingDateToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :issuing_date, :date
  end
end
