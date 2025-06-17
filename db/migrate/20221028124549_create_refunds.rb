# frozen_string_literal: true

class CreateRefunds < ActiveRecord::Migration[7.0]
  def change
    create_table :refunds, id: :uuid do |t|
      t.references :payment, type: :uuid, null: false, foreign_key: true, index: true
      t.references :credit_note, type: :uuid, null: false, foreign_key: true, index: true
      t.references :payment_provider, type: :uuid, null: false, foreign_key: true, index: true
      t.references :payment_provider_customer, type: :uuid, null: false, foreign_key: true, index: true
      t.bigint :amount_cents, null: false, default: 0
      t.string :amount_currency, null: false
      t.string :status, null: false
      t.string :provider_refund_id, null: false
      t.timestamps
    end
  end
end
