# frozen_string_literal: true

class ChangeDefaultInvoiceVersionToV4 < ActiveRecord::Migration[7.0]
  def change
    change_column_default :invoices, :version_number, from: 3, to: 4
  end
end
