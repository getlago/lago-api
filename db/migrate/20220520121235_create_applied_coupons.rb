# frozen_string_literal: true

class CreateAppliedCoupons < ActiveRecord::Migration[7.0]
  def change
    create_table :applied_coupons, id: :uuid do |t|
      t.references :coupon, type: :uuid, null: false
      t.references :customer, type: :uuid, null: false

      t.integer :status, null: false, default: 0

      t.integer :amount_cents, null: false
      t.string :amount_currency, null: false

      t.index %i[coupon_id customer_id], unique: true

      t.timestamps
    end
  end
end
