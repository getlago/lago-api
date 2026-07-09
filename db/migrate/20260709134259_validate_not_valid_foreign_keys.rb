# frozen_string_literal: true

class ValidateNotValidForeignKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :wallet_transactions, :billing_entities
    validate_foreign_key :wallet_transactions, :payment_methods
    validate_foreign_key :wallets, :billing_entities
    validate_foreign_key :wallets, :payment_methods
    validate_foreign_key :subscriptions, :billing_entities
    validate_foreign_key :subscriptions, :payment_methods
    validate_foreign_key :payments, :payment_methods
    validate_foreign_key :recurring_transaction_rules, :payment_methods
    validate_foreign_key :adjusted_fees, :fixed_charges
    validate_foreign_key :invoice_subscriptions, column: :regenerated_invoice_id
  end
end
