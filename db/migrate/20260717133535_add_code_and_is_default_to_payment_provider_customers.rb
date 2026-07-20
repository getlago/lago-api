# frozen_string_literal: true

class AddCodeAndIsDefaultToPaymentProviderCustomers < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      change_table :payment_provider_customers, bulk: true do |t|
        t.string :code
        t.boolean :is_default, default: false, null: false
      end
    end
  end
end
