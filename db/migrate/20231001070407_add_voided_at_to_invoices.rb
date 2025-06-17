# frozen_string_literal: true

class AddVoidedAtToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :voided_at, :datetime
  end
end
