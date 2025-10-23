# frozen_string_literal: true

class AddPaymentMethodToRecurringTransactionRules < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      change_table :recurring_transaction_rules, bulk: true do |t|
        t.references :payment_method, type: :uuid, null: true, index: {algorithm: :concurrently}
        t.enum :payment_method_type, enum_type: "payment_method_types", default: "provider", null: false
      end
    end
    add_foreign_key :recurring_transaction_rules, :payment_methods, validate: false
  end
end
