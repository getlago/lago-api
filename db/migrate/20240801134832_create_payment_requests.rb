# frozen_string_literal: true

class CreatePaymentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_requests, id: :uuid do |t|
      t.references :customer, type: :uuid, index: true, foreign_key: true, null: false
      t.references :payment, type: :uuid, index: true, foreign_key: true
      t.uuid :payment_requestable_id, null: false
      t.string :payment_requestable_type, null: false, default: "Invoice"
      t.bigint :amount_cents, null: false, default: 0
      t.string :amount_currency, null: false
      t.string :email, null: false
      t.timestamps
    end
  end
end
