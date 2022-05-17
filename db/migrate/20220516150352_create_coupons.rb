# frozen_string_literal: true

class CreateCoupons < ActiveRecord::Migration[7.0]
  def change
    create_table :coupons, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, index: true

      t.string :name, null: false
      t.string :code, null: true

      t.integer :coupon_type, null: false
      t.bigint :amount_cents, null: true
      t.string :amount_currency, null: true
      t.integer :day_count, null: true

      t.integer :expiration, null: false
      t.integer :expiration_users, null: true
      t.integer :expiration_duration, null: true

      t.index %i[organization_id code], unique: true, where: 'code IS NOT NULL'

      t.timestamps
    end
  end
end
