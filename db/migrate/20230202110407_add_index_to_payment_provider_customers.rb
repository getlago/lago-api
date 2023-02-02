# frozen_string_literal: true

class AddIndexToPaymentProviderCustomers < ActiveRecord::Migration[7.0]
  def change
    add_index :payment_provider_customers, %i[customer_id type], unique: true
    remove_index :payment_provider_customers, :customer_id
  end
end
