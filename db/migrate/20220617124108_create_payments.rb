# frozen_string_literal: true

class CreatePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :payments, id: :uuid do |t|
      t.references :invoice, type: :uuid, null: false, foreign_key: true, index: true
      t.references :payment_provider, type: :uuid, foreign_key: true, index: true
      t.references :payment_provider_customer, type: :uuid

      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false

      t.string :provider_payment_id, null: false
      t.string :status, null: false

      t.timestamps
    end
  end
end
