# frozen_string_literal: true

class ValidateX402ConnectionForeignKeyOnInvoices < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :invoices, :x402_connections
  end
end
