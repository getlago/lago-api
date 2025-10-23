# frozen_string_literal: true

class AddPaymentMethodToCoreTables < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_enum :payment_method_types, %w[provider manual]

    safety_assured do
      change_table :subscriptions, bulk: true do |t|
        t.references :payment_method, type: :uuid, null: true, index: {algorithm: :concurrently}
        t.enum :payment_method_type, enum_type: 'payment_method_types', default: 'provider', null: false
      end
    end
    add_foreign_key :subscriptions, :payment_methods, validate: false

    safety_assured do
      change_table :wallets, bulk: true do |t|
        t.references :payment_method, type: :uuid, null: true, index: {algorithm: :concurrently}
        t.enum :payment_method_type, enum_type: 'payment_method_types', default: 'provider', null: false
      end
    end
    add_foreign_key :wallets, :payment_methods, validate: false

    safety_assured do
      change_table :recurring_transaction_rules, bulk: true do |t|
        t.references :payment_method, type: :uuid, null: true, index: {algorithm: :concurrently}
        t.enum :payment_method_type, enum_type: 'payment_method_types', default: 'provider', null: false
      end
    end
    add_foreign_key :recurring_transaction_rules, :payment_methods, validate: false
  end
end