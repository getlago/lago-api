# frozen_string_literal: true

class AddX402ConnectionForeignKeyToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :invoices, :x402_connections, validate: false, if_not_exists: true
  end
end
