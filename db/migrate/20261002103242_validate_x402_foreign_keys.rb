# frozen_string_literal: true

class ValidateX402ForeignKeys < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :x402_connections, :organizations
    validate_foreign_key :x402_settlements, :organizations
    validate_foreign_key :x402_settlements, :customers
    validate_foreign_key :x402_settlements, :subscriptions
    validate_foreign_key :x402_settlements, :wallet_transactions
    validate_foreign_key :x402_settlements, :payments
    validate_foreign_key :x402_settlements, :invoices
  end
end
