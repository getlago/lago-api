# frozen_string_literal: true

class AddManualPaymentMethodColumn < ActiveRecord::Migration[8.0]
  def change
    add_column :recurring_transaction_rules, :manual_payment_method, :boolean, default: false, null: false
    add_column :subscriptions, :manual_payment_method, :boolean, default: false, null: false
    add_column :wallets, :manual_payment_method, :boolean, default: false, null: false
  end
end
