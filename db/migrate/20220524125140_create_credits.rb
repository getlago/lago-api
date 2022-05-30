# frozen_string_literal: true

class CreateCredits < ActiveRecord::Migration[7.0]
  def change
    create_table :credits, type: :uuid do |t|
      t.references :invoice, type: :uuid, foreign_key: true, index: true
      t.references :applied_coupon, type: :uuid, foreign_key: true, index: true

      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false

      t.timestamps
    end
  end
end
