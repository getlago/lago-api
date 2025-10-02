# frozen_string_literal: true

class AddPaymentMethodId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :recurring_transaction_rules, :payment_method, type: :uuid, index: {algorithm: :concurrently}
    add_reference :subscriptions, :payment_method, type: :uuid, index: {algorithm: :concurrently}
    add_reference :wallets, :payment_method, type: :uuid, index: {algorithm: :concurrently}
  end
end
