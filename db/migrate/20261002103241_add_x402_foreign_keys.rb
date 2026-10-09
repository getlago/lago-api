# frozen_string_literal: true

class AddX402ForeignKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_foreign_key :x402_connections, :organizations, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :organizations, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :customers, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :subscriptions, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :wallet_transactions, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :payments, validate: false, if_not_exists: true
    add_foreign_key :x402_settlements, :invoices, validate: false, if_not_exists: true
  end
end
