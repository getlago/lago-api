# frozen_string_literal: true

class AddPaymentTermToSubscriptionsAndWallets < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :payment_term, :jsonb
    add_column :wallets, :payment_term, :jsonb
  end
end
