# frozen_string_literal: true

class CreatePaymentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_requests, id: :uuid do |t|
      t.references :customer, type: :uuid, index: true, foreign_key: true, null: false
      t.uuid :payment_requestable_id, null: false
      t.string :payment_requestable_type, null: false, default: "Invoice"
      t.bigint :amount_cents, null: false, default: 0
      t.string :amount_currency, null: false
      t.string :email, null: false
      t.timestamps
    end
    safety_assured do
      change_table :payments, bulk: true do |t|
        t.uuid :payment_request_id
      end
      add_foreign_key :payments, :payment_requests
    end
  end
end
