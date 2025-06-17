# frozen_string_literal: true

class ChangeDefaultInvoiceVersion < ActiveRecord::Migration[7.0]
  def change
    change_column_default :invoices, :version_number, from: 2, to: 3
  end
end
