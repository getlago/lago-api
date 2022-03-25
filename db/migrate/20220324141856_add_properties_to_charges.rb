# frozen_string_literal: true

class AddPropertiesToCharges < ActiveRecord::Migration[7.0]
  def change
    change_table :charges do |t|
      t.integer :amount_cents, null: false
      t.string :amount_currency, null: false
      t.integer :frequency, null: false
      t.boolean :pro_rata, null: false
      t.float :vat_rate
    end
  end
end
