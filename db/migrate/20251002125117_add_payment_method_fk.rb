# frozen_string_literal: true

class AddPaymentMethodFk < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :recurring_transaction_rules, :payment_methods, validate: false
    add_foreign_key :subscriptions, :payment_methods, validate: false
    add_foreign_key :wallets, :payment_methods, validate: false
  end
end
