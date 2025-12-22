# frozen_string_literal: true

class AddPaymentMethodToPayments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_reference :payments, :payment_method, null: true, type: :uuid, index: {algorithm: :concurrently}
    end
    add_foreign_key :payments, :payment_methods, validate: false
  end
end
