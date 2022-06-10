# frozen_string_literal: true

class CreatePaymentProviderCustomers < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_provider_customers, id: :uuid do |t|
      t.references :customer, type: :uuid, index: true, null: false, foreign_key: true
      t.string :type, null: false
      t.string :external_customer_id, null: false, index: true
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
